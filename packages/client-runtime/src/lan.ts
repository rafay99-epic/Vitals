import {
  type DeviceInfo,
  type LanAdvert,
  type LanOpen,
  LAN_PROLOGUE,
  LanAccept,
  LanAdvert as LanAdvertSchema,
  LanPairResult,
  PROTOCOL_VERSION,
} from "@vitals/contracts";
import { type KeyPair, type Transport, fromBase64Url, initiator, matchCode, toBase64Url } from "@vitals/noise";
import * as Schema from "effect/Schema";
import type * as Socket from "effect/socket/Socket";

export type RawSocket = (url: string) => Socket.WebSocketLike;

type EventName = "open" | "message" | "error" | "close";
type Listener = (event: Socket.WebSocketEvent) => void;

const decodeAccept = Schema.decodeUnknownOption(Schema.fromJsonString(LanAccept));
const decodeResult = Schema.decodeUnknownOption(Schema.fromJsonString(LanPairResult));
const decodeAdvert = Schema.decodeUnknownOption(LanAdvertSchema);

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const prologue = encoder.encode(LAN_PROLOGUE);
const noAd = new Uint8Array(0);

const textOf = (event: unknown, key: string): string => {
  const value: unknown = typeof event === "object" && event !== null ? Reflect.get(event, key) : undefined;
  return typeof value === "string" ? value : "";
};

/** Says how a Wi-Fi socket ended before its handshake finished, for the phone's journal. */
export const earlyEnd = (opened: boolean, event: unknown): string => {
  const said = textOf(event, "message") || textOf(event, "reason");
  if (!opened) return said === "" ? "no connection" : `no connection: ${said}`;
  const code: unknown = typeof event === "object" && event !== null ? Reflect.get(event, "code") : undefined;
  return `the Mac closed it before answering${typeof code === "number" ? ` (${String(code)}${said === "" ? "" : ` ${said}`})` : ""}`;
};

const bytesOf = (data: unknown): Uint8Array | null => {
  if (data instanceof ArrayBuffer) return new Uint8Array(data);
  return data instanceof Uint8Array ? data : null;
};

const owned = (bytes: Uint8Array): Uint8Array<ArrayBuffer> => new Uint8Array(bytes);

export const lanSocketUrl = (host: string, port: number): string => `ws://${host.includes(":") ? `[${host}]` : host}:${port}/lan`;

export const lanAdvertUrl = (host: string, port: number): string =>
  `http://${host.includes(":") ? `[${host}]` : host}:${port}/.well-known/vitals`;

const handshake = (macKey: Uint8Array, device: KeyPair, open: LanOpen) => {
  const noise = initiator({ localStatic: device, remoteStatic: macKey, prologue });
  return {
    first: owned(noise.writeMessage1(encoder.encode(JSON.stringify(open)))),
    finish: (message: Uint8Array) => {
      const { payload, transport } = noise.readMessage2(message);
      const accept = decodeAccept(decoder.decode(payload));
      return { accept: accept._tag === "Some" ? accept.value : null, transport };
    },
  };
};

export interface LanSocketOptions {
  readonly macKey: Uint8Array;
  readonly device: KeyPair;
  readonly client: string;
  readonly raw: RawSocket;
  readonly onRejected?: (reason: string) => void;
  /** Why the socket ended before the Mac's handshake reply, when it did. */
  readonly onEndedEarly?: (detail: string) => void;
}

export const openLanSocket = (url: string, options: LanSocketOptions): Socket.WebSocketLike => {
  const raw = options.raw(url);
  const listeners = new Map<EventName, Map<Listener, boolean>>();
  const start = handshake(options.macKey, options.device, { t: "connect", v: PROTOCOL_VERSION, client: options.client });
  let transport: Transport | null = null;
  let readyState = 0;
  let opened = false;
  let failure: unknown = null;

  const emit = (name: EventName, event: Socket.WebSocketEvent) => {
    for (const [listener, once] of listeners.get(name) ?? []) {
      if (once) listeners.get(name)?.delete(listener);
      listener(event);
    }
  };

  const fail = (code: number, reason: string) => {
    readyState = 3;
    raw.close(code, reason);
    emit("error", { type: "error", reason });
    emit("close", { type: "close", code, reason });
  };

  raw.addEventListener(
    "open",
    () => {
      opened = true;
      raw.send(start.first);
    },
    { once: true },
  );
  raw.addEventListener("error", (event) => {
    failure = event;
    if (readyState < 3) emit("error", event);
  });
  raw.addEventListener("close", (event) => {
    if (readyState === 3) return;
    if (transport === null) options.onEndedEarly?.(earlyEnd(opened, opened ? event : (failure ?? event)));
    readyState = 3;
    emit("close", event);
  });
  raw.addEventListener("message", (event) => {
    const bytes = bytesOf(event.data);
    if (bytes === null) return fail(4400, "unexpected frame");
    try {
      if (transport !== null) {
        emit("message", { type: "message", data: decoder.decode(transport.receive.decrypt(noAd, bytes)) });
        return;
      }
      const finished = start.finish(bytes);
      if (finished.accept?.t !== "ready") {
        options.onRejected?.(finished.accept?.t ?? "rejected");
        return fail(4401, finished.accept?.t ?? "rejected");
      }
      transport = finished.transport;
      readyState = 1;
      emit("open", { type: "open" });
    } catch {
      options.onEndedEarly?.("the Mac's key did not match");
      fail(4400, "the Mac's key did not match");
    }
  });

  return {
    get readyState() {
      return readyState;
    },
    addEventListener: (name, listener, listenerOptions) => {
      const forName = listeners.get(name) ?? new Map<Listener, boolean>();
      forName.set(listener, listenerOptions?.once === true);
      listeners.set(name, forName);
    },
    removeEventListener: (name, listener) => {
      listeners.get(name)?.delete(listener);
    },
    send: (data) => {
      if (transport === null) return;
      raw.send(owned(transport.send.encrypt(noAd, typeof data === "string" ? encoder.encode(data) : data)));
    },
    close: (code, reason) => {
      if (readyState >= 2) return;
      readyState = 2;
      raw.close(code, reason);
    },
  };
};

export type LanPairOutcome =
  | { readonly ok: true; readonly result: Extract<LanPairResult, { readonly t: "paired" }> }
  | {
      readonly ok: false;
      readonly reason: "denied" | "expired" | "busy" | "incompatible" | "unreachable" | "mismatch" | "cancelled";
      /** What actually happened on the socket, for the phone's journal. */
      readonly detail: string;
    };

export interface LanPairOptions {
  readonly host: string;
  readonly port: number;
  readonly macKey: Uint8Array;
  readonly device: KeyPair;
  readonly info: DeviceInfo;
  readonly raw: RawSocket;
  readonly onWaiting: (code: string, expiresAt: number) => void;
}

export const pairOverLan = (options: LanPairOptions): { readonly outcome: Promise<LanPairOutcome>; readonly cancel: () => void } => {
  const raw = options.raw(lanSocketUrl(options.host, options.port));
  const start = handshake(options.macKey, options.device, { t: "pair", v: PROTOCOL_VERSION, device: options.info });
  let transport: Transport | null = null;
  let opened = false;
  let settle: (outcome: LanPairOutcome) => void = () => {};
  const outcome = new Promise<LanPairOutcome>((resolve) => {
    settle = (value) => {
      settle = () => {};
      resolve(value);
      raw.close(1000, "done");
    };
  });

  type Failed = Extract<LanPairOutcome, { readonly ok: false }>["reason"];
  const fail = (reason: Failed, detail: string) => settle({ ok: false, reason, detail });

  raw.addEventListener(
    "open",
    () => {
      opened = true;
      raw.send(start.first);
    },
    { once: true },
  );
  raw.addEventListener("close", (event) =>
    transport === null ? fail("unreachable", earlyEnd(opened, event)) : fail("expired", "the Mac closed it while waiting"),
  );
  raw.addEventListener("error", (event) => fail("unreachable", earlyEnd(opened, event)));
  raw.addEventListener("message", (event) => {
    const bytes = bytesOf(event.data);
    if (bytes === null) return fail("mismatch", "the Mac sent text, not a handshake");
    try {
      if (transport === null) {
        const finished = start.finish(bytes);
        transport = finished.transport;
        const accept = finished.accept;
        if (accept?.t === "waiting") return options.onWaiting(matchCode(transport.handshakeHash), accept.expiresAt);
        if (accept?.t === "busy" || accept?.t === "incompatible") return fail(accept.t, `the Mac answered ${accept.t}`);
        return fail("mismatch", `the Mac answered ${accept?.t ?? "something unreadable"}`);
      }
      const result = decodeResult(decoder.decode(transport.receive.decrypt(noAd, bytes)));
      if (result._tag === "None") return fail("mismatch", "the Mac's answer was unreadable");
      if (result.value.t === "paired") return settle({ ok: true, result: result.value });
      fail(result.value.t, `the Mac answered ${result.value.t}`);
    } catch {
      fail("mismatch", transport === null ? "the Mac's key did not match" : "the Mac's answer did not decrypt");
    }
  });

  return { outcome, cancel: () => fail("cancelled", "cancelled on the phone") };
};

export type LanProbe = { readonly ok: true; readonly advert: LanAdvert } | { readonly ok: false; readonly why: string };

const isTimeout = (error: unknown): boolean => error instanceof Error && (error.name === "TimeoutError" || error.name === "AbortError");

/** Asks host:port whether it is a Vitals Mac, and with which key. A miss says why. */
export const probeLan = async (
  host: string,
  port: number,
  expectedKey: string | null,
  fetchImpl: typeof globalThis.fetch,
  timeoutMs = 2_500,
): Promise<LanProbe> => {
  try {
    const response = await fetchImpl(lanAdvertUrl(host, port), { signal: AbortSignal.timeout(timeoutMs) });
    if (!response.ok) return { ok: false, why: `answered HTTP ${String(response.status)}` };
    const advert = decodeAdvert(await response.json());
    if (advert._tag === "None") return { ok: false, why: "answered, but not as Vitals" };
    if (expectedKey !== null && advert.value.key !== expectedKey) return { ok: false, why: "a Vitals Mac with a different key" };
    return { ok: true, advert: advert.value };
  } catch (error) {
    if (isTimeout(error)) return { ok: false, why: `no answer in ${String(timeoutMs / 1000)} s` };
    return { ok: false, why: error instanceof Error && error.message !== "" ? `no connection: ${error.message}` : "no connection" };
  }
};

export const macKeyBytes = (key: string): Uint8Array => fromBase64Url(key);

export const deviceKeyText = (pair: KeyPair): string => toBase64Url(pair.publicKey);
