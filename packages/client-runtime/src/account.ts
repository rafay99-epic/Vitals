import { OpenAlerts, SessionInfo } from "@vitals/contracts";
import * as Schema from "effect/Schema";

type Fetch = typeof globalThis.fetch;

const decodeSession = Schema.decodeUnknownResult(SessionInfo);
const decodeAlerts = Schema.decodeUnknownResult(OpenAlerts);

export const authHeaders = (token: string | null): Record<string, string> =>
  token === null ? {} : { authorization: `Bearer ${token}` };

export type SessionLookup =
  | { readonly _tag: "Paired"; readonly session: SessionInfo }
  | { readonly _tag: "Unpaired" }
  | { readonly _tag: "Unreachable" };

export const fetchSession = async (
  baseUrl: string,
  token: string | null,
  fetchImpl: Fetch = globalThis.fetch.bind(globalThis),
): Promise<SessionLookup> => {
  try {
    const response = await fetchImpl(`${baseUrl}/api/session`, {
      headers: authHeaders(token),
      signal: AbortSignal.timeout(10_000),
    });
    if (response.status === 204 || response.status === 401) return { _tag: "Unpaired" };
    if (!response.ok) return { _tag: "Unreachable" };
    const decoded = decodeSession(await response.json());
    return decoded._tag === "Success" ? { _tag: "Paired", session: decoded.success } : { _tag: "Unreachable" };
  } catch {
    return { _tag: "Unreachable" };
  }
};

export const unpair = async (
  baseUrl: string,
  token: string | null,
  fetchImpl: Fetch = globalThis.fetch.bind(globalThis),
): Promise<boolean> => {
  try {
    const response = await fetchImpl(`${baseUrl}/api/unpair`, {
      method: "POST",
      headers: authHeaders(token),
      signal: AbortSignal.timeout(10_000),
    });
    return response.ok || response.status === 401;
  } catch {
    return false;
  }
};

export const fetchOpenAlerts = async (
  baseUrl: string,
  token: string | null,
  afterSeq: number,
  fetchImpl: Fetch = globalThis.fetch.bind(globalThis),
): Promise<OpenAlerts | null> => {
  try {
    const response = await fetchImpl(`${baseUrl}/api/alerts?after=${afterSeq}`, {
      headers: authHeaders(token),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) return null;
    const decoded = decodeAlerts(await response.json());
    return decoded._tag === "Success" ? decoded.success : null;
  } catch {
    return null;
  }
};
