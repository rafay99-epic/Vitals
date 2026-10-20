import { type DeviceInfo, PAIRING_ALPHABET, PAIRING_CODE_LENGTH, PairResponse } from "@vitals/contracts";
import * as Schema from "effect/Schema";

const decodeResponse = Schema.decodeUnknownResult(PairResponse);

export interface PairingLink {
  readonly baseUrl: string;
  readonly code: string;
}

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
    const code = normalizeCode(new URLSearchParams(url.hash.replace(/^#/, "")).get("code") ?? "");
    if (code.length !== PAIRING_CODE_LENGTH) return null;
    return { baseUrl: url.origin, code };
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
  link: PairingLink,
  device: DeviceInfo,
  fetchImpl: typeof globalThis.fetch = globalThis.fetch.bind(globalThis),
): Promise<PairOutcome> => {
  try {
    const response = await fetchImpl(`${link.baseUrl}/api/pair`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: link.code, device }),
      signal: AbortSignal.timeout(15_000),
    });
    const body: unknown = await response.json();
    if (!response.ok) {
      const message =
        typeof body === "object" && body !== null && "message" in body && typeof body.message === "string"
          ? body.message
          : `Pairing failed (${response.status})`;
      return { ok: false, message };
    }
    const decoded = decodeResponse(body);
    return decoded._tag === "Success" ? { ok: true, response: decoded.success } : { ok: false, message: "Unexpected reply from the Mac" };
  } catch {
    return { ok: false, message: "Could not reach the Mac. Is Tailscale on?" };
  }
};
