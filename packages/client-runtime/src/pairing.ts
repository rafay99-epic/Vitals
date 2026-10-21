import { type DeviceInfo, PAIRING_ALPHABET, PAIRING_CODE_LENGTH, PairResponse } from "@vitals/contracts";
import * as Schema from "effect/Schema";

const decodeResponse = Schema.decodeUnknownResult(PairResponse);

export interface PairingLink {
  readonly baseUrl: string;
  readonly code: string;
  readonly macKey: string | null;
}

const LAN_KEY = /^[A-Za-z0-9_-]{43}$/;

export const normalizeCode = (raw: string): string =>
  raw
    .toUpperCase()
    .split("")
    .filter((char) => PAIRING_ALPHABET.includes(char))
    .join("");

export const parsePairingUrl = (raw: string): PairingLink | null => {
  try {
    const url = new URL(raw.trim());
    if (url.protocol !== "https:" && url.protocol !== "http:") return null;
    const fragment = new URLSearchParams(url.hash.replace(/^#/, ""));
    const code = normalizeCode(fragment.get("code") ?? "");
    if (code.length !== PAIRING_CODE_LENGTH) return null;
    const key = fragment.get("key");
    return { baseUrl: url.origin, code, macKey: key !== null && LAN_KEY.test(key) ? key : null };
  } catch {
    return null;
  }
};

export const parsePairingDeepLink = (raw: string): PairingLink | null => {
  const query = /^[a-z][a-z0-9+.-]*:\/\/pair\/?\?(.+)$/i.exec(raw.trim())?.[1];
  if (query === undefined || /^https?:/i.test(raw.trim())) return null;
  const link = new URLSearchParams(query).get("link");
  return link === null ? null : parsePairingUrl(link);
};

export type PairOutcome =
  | { readonly ok: true; readonly response: PairResponse }
  | { readonly ok: false; readonly message: string };

export const pair = async (
  link: Pick<PairingLink, "baseUrl" | "code">,
  device: DeviceInfo,
  fetchImpl: typeof globalThis.fetch = globalThis.fetch.bind(globalThis),
  lanKey: string | null = null,
): Promise<PairOutcome> => {
  const response = await fetchImpl(`${link.baseUrl}/api/pair`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(lanKey === null ? { code: link.code, device } : { code: link.code, device, lanKey }),
    signal: AbortSignal.timeout(15_000),
  }).catch(() => null);
  if (response === null) return { ok: false, message: "Could not reach the Mac. Check that Tailscale is on, on both." };
  const body: unknown = await response.json().catch(() => null);
  if (!response.ok) {
    const message =
      typeof body === "object" && body !== null && "message" in body && typeof body.message === "string"
        ? body.message
        : `The Mac answered ${response.status}. Check the address and try again.`;
    return { ok: false, message };
  }
  const decoded = decodeResponse(body);
  return decoded._tag === "Success" ? { ok: true, response: decoded.success } : { ok: false, message: "Unexpected reply from the Mac" };
};
