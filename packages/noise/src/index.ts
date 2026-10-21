import { chacha20poly1305 } from "@noble/ciphers/chacha.js";
import { x25519 } from "@noble/curves/ed25519.js";
import { hmac } from "@noble/hashes/hmac.js";
import { sha256 } from "@noble/hashes/sha2.js";

export const PROTOCOL_NAME = "Noise_IK_25519_ChaChaPoly_SHA256";

const HASH_LEN = 32;
const KEY_LEN = 32;
const TAG_LEN = 16;
const MAX_NONCE = Number.MAX_SAFE_INTEGER;

export interface KeyPair {
  readonly secretKey: Uint8Array;
  readonly publicKey: Uint8Array;
}

export class NoiseError extends Error {
  override readonly name = "NoiseError";
}

const encoder = new TextEncoder();

const concat = (...parts: ReadonlyArray<Uint8Array>): Uint8Array => {
  const out = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
};

const empty = new Uint8Array(0);

export const keyPairFromSecret = (secretKey: Uint8Array): KeyPair => ({ secretKey, publicKey: x25519.getPublicKey(secretKey) });

let randomSource = (length: number): Uint8Array => crypto.getRandomValues(new Uint8Array(length));

export const setRandomSource = (source: (length: number) => Uint8Array): void => {
  randomSource = source;
};

export const generateKeyPair = (): KeyPair => keyPairFromSecret(randomSource(KEY_LEN));

const dh = (pair: KeyPair, publicKey: Uint8Array): Uint8Array => x25519.getSharedSecret(pair.secretKey, publicKey);

const hkdf = (chainingKey: Uint8Array, input: Uint8Array): readonly [Uint8Array, Uint8Array] => {
  const tempKey = hmac(sha256, chainingKey, input);
  const first = hmac(sha256, tempKey, Uint8Array.of(1));
  const second = hmac(sha256, tempKey, concat(first, Uint8Array.of(2)));
  return [first, second];
};

const nonceBytes = (counter: number): Uint8Array => {
  const nonce = new Uint8Array(12);
  const view = new DataView(nonce.buffer);
  view.setUint32(4, counter >>> 0, true);
  view.setUint32(8, Math.floor(counter / 2 ** 32), true);
  return nonce;
};

export class CipherState {
  private counter = 0;
  private readonly key: Uint8Array | null;

  constructor(key: Uint8Array | null) {
    this.key = key;
  }

  private next(): Uint8Array {
    if (this.counter >= MAX_NONCE) throw new NoiseError("nonce exhausted");
    const nonce = nonceBytes(this.counter);
    this.counter += 1;
    return nonce;
  }

  encrypt(ad: Uint8Array, plaintext: Uint8Array): Uint8Array {
    if (this.key === null) return plaintext;
    return chacha20poly1305(this.key, this.next(), ad).encrypt(plaintext);
  }

  decrypt(ad: Uint8Array, ciphertext: Uint8Array): Uint8Array {
    if (this.key === null) return ciphertext;
    if (ciphertext.length < TAG_LEN) throw new NoiseError("message too short");
    try {
      return chacha20poly1305(this.key, this.next(), ad).decrypt(ciphertext);
    } catch {
      throw new NoiseError("message failed authentication");
    }
  }
}

class SymmetricState {
  private chainingKey: Uint8Array;
  private hash: Uint8Array;
  private cipher = new CipherState(null);

  constructor(prologue: Uint8Array) {
    const name = encoder.encode(PROTOCOL_NAME);
    this.hash = name.length <= HASH_LEN ? concat(name, new Uint8Array(HASH_LEN - name.length)) : sha256(name);
    this.chainingKey = this.hash;
    this.mixHash(prologue);
  }

  get handshakeHash(): Uint8Array {
    return this.hash;
  }

  mixHash(data: Uint8Array): void {
    this.hash = sha256(concat(this.hash, data));
  }

  mixKey(input: Uint8Array): void {
    const [chainingKey, key] = hkdf(this.chainingKey, input);
    this.chainingKey = chainingKey;
    this.cipher = new CipherState(key.slice(0, KEY_LEN));
  }

  encryptAndHash(plaintext: Uint8Array): Uint8Array {
    const ciphertext = this.cipher.encrypt(this.hash, plaintext);
    this.mixHash(ciphertext);
    return ciphertext;
  }

  decryptAndHash(ciphertext: Uint8Array): Uint8Array {
    const plaintext = this.cipher.decrypt(this.hash, ciphertext);
    this.mixHash(ciphertext);
    return plaintext;
  }

  split(): readonly [CipherState, CipherState] {
    const [first, second] = hkdf(this.chainingKey, empty);
    return [new CipherState(first.slice(0, KEY_LEN)), new CipherState(second.slice(0, KEY_LEN))];
  }
}

export interface Transport {
  readonly send: CipherState;
  readonly receive: CipherState;
  readonly handshakeHash: Uint8Array;
  readonly remoteStatic: Uint8Array;
}

export interface InitiatorOptions {
  readonly localStatic: KeyPair;
  readonly remoteStatic: Uint8Array;
  readonly prologue?: Uint8Array;
  readonly ephemeral?: KeyPair;
}

export interface ResponderOptions {
  readonly localStatic: KeyPair;
  readonly prologue?: Uint8Array;
  readonly ephemeral?: KeyPair;
}

const take = (message: Uint8Array, offset: number, length: number): Uint8Array => {
  if (message.length < offset + length) throw new NoiseError("handshake message too short");
  return message.subarray(offset, offset + length);
};

export const initiator = (options: InitiatorOptions) => {
  const state = new SymmetricState(options.prologue ?? empty);
  const ephemeral = options.ephemeral ?? generateKeyPair();
  state.mixHash(options.remoteStatic);
  return {
    writeMessage1: (payload: Uint8Array): Uint8Array => {
      state.mixHash(ephemeral.publicKey);
      state.mixKey(dh(ephemeral, options.remoteStatic));
      const encryptedStatic = state.encryptAndHash(options.localStatic.publicKey);
      state.mixKey(dh(options.localStatic, options.remoteStatic));
      return concat(ephemeral.publicKey, encryptedStatic, state.encryptAndHash(payload));
    },
    readMessage2: (message: Uint8Array): { readonly payload: Uint8Array; readonly transport: Transport } => {
      const remoteEphemeral = take(message, 0, KEY_LEN);
      state.mixHash(remoteEphemeral);
      state.mixKey(dh(ephemeral, remoteEphemeral));
      state.mixKey(dh(options.localStatic, remoteEphemeral));
      const payload = state.decryptAndHash(message.subarray(KEY_LEN));
      const [send, receive] = state.split();
      return { payload, transport: { send, receive, handshakeHash: state.handshakeHash, remoteStatic: options.remoteStatic } };
    },
  };
};

export const responder = (options: ResponderOptions) => {
  const state = new SymmetricState(options.prologue ?? empty);
  const ephemeral = options.ephemeral ?? generateKeyPair();
  state.mixHash(options.localStatic.publicKey);
  let remoteEphemeral: Uint8Array | null = null;
  let remoteStatic: Uint8Array | null = null;
  return {
    readMessage1: (message: Uint8Array): { readonly payload: Uint8Array; readonly remoteStatic: Uint8Array } => {
      const theirEphemeral = take(message, 0, KEY_LEN).slice();
      state.mixHash(theirEphemeral);
      state.mixKey(dh(options.localStatic, theirEphemeral));
      const theirStatic = state.decryptAndHash(take(message, KEY_LEN, KEY_LEN + TAG_LEN)).slice();
      state.mixKey(dh(options.localStatic, theirStatic));
      const payload = state.decryptAndHash(message.subarray(KEY_LEN * 2 + TAG_LEN));
      remoteEphemeral = theirEphemeral;
      remoteStatic = theirStatic;
      return { payload, remoteStatic: theirStatic };
    },
    writeMessage2: (payload: Uint8Array): { readonly message: Uint8Array; readonly transport: Transport } => {
      if (remoteEphemeral === null || remoteStatic === null) throw new NoiseError("read message 1 first");
      state.mixHash(ephemeral.publicKey);
      state.mixKey(dh(ephemeral, remoteEphemeral));
      state.mixKey(dh(ephemeral, remoteStatic));
      const message = concat(ephemeral.publicKey, state.encryptAndHash(payload));
      const [receive, send] = state.split();
      return { message, transport: { send, receive, handshakeHash: state.handshakeHash, remoteStatic } };
    },
  };
};

export const matchCode = (handshakeHash: Uint8Array): string => {
  const view = new DataView(handshakeHash.buffer, handshakeHash.byteOffset, 4);
  return String(view.getUint32(0, false) % 10_000).padStart(4, "0");
};

export const fingerprint = (publicKey: Uint8Array): string => toBase64Url(sha256(publicKey).subarray(0, 16));

export const toBase64Url = (bytes: Uint8Array): string =>
  btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");

export const fromBase64Url = (text: string): Uint8Array => {
  const padded = text.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - (text.length % 4)) % 4);
  try {
    return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
  } catch {
    throw new NoiseError("invalid base64url");
  }
};
