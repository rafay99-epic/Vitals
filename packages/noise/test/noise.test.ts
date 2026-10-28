import { describe, expect, test } from "bun:test";

import {
  fromBase64Url,
  generateKeyPair,
  initiator,
  keyPairFromSecret,
  matchCode,
  NoiseError,
  responder,
  toBase64Url,
} from "../src/index.ts";
import vector from "./vectors.json" with { type: "json" };

const hex = (text: string): Uint8Array => Uint8Array.from(text.match(/../g) ?? [], (byte) => Number.parseInt(byte, 16));
const toHex = (bytes: Uint8Array): string => Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");

describe("Noise_IK_25519_ChaChaPoly_SHA256", () => {
  test("matches the cacophony vector byte for byte", () => {
    const client = initiator({
      localStatic: keyPairFromSecret(hex(vector.init_static)),
      remoteStatic: hex(vector.init_remote_static),
      prologue: hex(vector.init_prologue),
      ephemeral: keyPairFromSecret(hex(vector.init_ephemeral)),
    });
    const server = responder({
      localStatic: keyPairFromSecret(hex(vector.resp_static)),
      prologue: hex(vector.resp_prologue),
      ephemeral: keyPairFromSecret(hex(vector.resp_ephemeral)),
    });
    const [first, second, ...rest] = vector.messages;
    if (first === undefined || second === undefined) throw new Error("vector has no handshake");

    const message1 = client.writeMessage1(hex(first.payload));
    expect(toHex(message1)).toBe(first.ciphertext);
    const read1 = server.readMessage1(message1);
    expect(toHex(read1.payload)).toBe(first.payload);
    expect(toHex(read1.remoteStatic)).toBe(toHex(keyPairFromSecret(hex(vector.init_static)).publicKey));

    const written2 = server.writeMessage2(hex(second.payload));
    expect(toHex(written2.message)).toBe(second.ciphertext);
    const read2 = client.readMessage2(written2.message);
    expect(toHex(read2.payload)).toBe(second.payload);
    expect(toHex(read2.transport.handshakeHash)).toBe(vector.handshake_hash);
    expect(toHex(written2.transport.handshakeHash)).toBe(vector.handshake_hash);

    rest.forEach((message, index) => {
      const fromClient = index % 2 === 0;
      const [sender, receiver] = fromClient ? [read2.transport, written2.transport] : [written2.transport, read2.transport];
      const ciphertext = sender.send.encrypt(new Uint8Array(0), hex(message.payload));
      expect(toHex(ciphertext)).toBe(message.ciphertext);
      expect(toHex(receiver.receive.decrypt(new Uint8Array(0), ciphertext))).toBe(message.payload);
    });
  });

  test("a responder with a different static key cannot read message 1", () => {
    const mac = generateKeyPair();
    const impostor = generateKeyPair();
    const message = initiator({ localStatic: generateKeyPair(), remoteStatic: mac.publicKey }).writeMessage1(new Uint8Array(0));
    expect(() => responder({ localStatic: impostor }).readMessage1(message)).toThrow(NoiseError);
  });

  test("a tampered transport frame is rejected", () => {
    const mac = generateKeyPair();
    const client = initiator({ localStatic: generateKeyPair(), remoteStatic: mac.publicKey });
    const server = responder({ localStatic: mac });
    server.readMessage1(client.writeMessage1(new Uint8Array(0)));
    const { message, transport: serverSide } = server.writeMessage2(new Uint8Array(0));
    const { transport: clientSide } = client.readMessage2(message);
    const frame = clientSide.send.encrypt(new Uint8Array(0), new TextEncoder().encode("shut down"));
    frame[0] = (frame[0] ?? 0) ^ 1;
    expect(() => serverSide.receive.decrypt(new Uint8Array(0), frame)).toThrow(NoiseError);
  });

  test("both sides derive the same four digit match code", () => {
    const mac = generateKeyPair();
    const client = initiator({ localStatic: generateKeyPair(), remoteStatic: mac.publicKey });
    const server = responder({ localStatic: mac });
    server.readMessage1(client.writeMessage1(new Uint8Array(0)));
    const { message, transport } = server.writeMessage2(new Uint8Array(0));
    const code = matchCode(client.readMessage2(message).transport.handshakeHash);
    expect(code).toMatch(/^\d{4}$/);
    expect(matchCode(transport.handshakeHash)).toBe(code);
  });

  test("base64url round-trips keys", () => {
    const key = generateKeyPair().publicKey;
    expect(fromBase64Url(toBase64Url(key))).toEqual(key);
    expect(toBase64Url(key)).not.toMatch(/[+/=]/);
  });
});
