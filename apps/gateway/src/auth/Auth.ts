import { type PairRequest, type PairResponse, type Scope, type SessionInfo, DEFAULT_PAIRED_SCOPES } from "@vitals/contracts";
import * as Context from "effect/Context";
import * as Deferred from "effect/Deferred";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Store } from "../persistence/Store.ts";
import { randomToken, type SessionMatch } from "../persistence/RemoteStore.ts";

const TICKET_TTL_MS = 60_000;

export type Session = SessionMatch & { readonly version: string };

export type Paired = Omit<PairResponse, "token"> & { readonly token: string };

export type AuthFailure =
  | { readonly reason: "identity"; readonly message: string }
  | { readonly reason: "credentials"; readonly message: string };

export class Auth extends Context.Service<
  Auth,
  {
    readonly ownerLogin: () => string | null;
    readonly setOwnerLogin: (login: string | null) => Effect.Effect<void>;
    readonly checkIdentity: (login: string | null) => AuthFailure | null;
    readonly pair: (request: PairRequest, login: string | null) => Paired | AuthFailure;
    readonly session: (token: string) => SessionInfo | null;
    readonly unpair: (token: string) => Effect.Effect<boolean>;
    readonly issueTicket: (bearer: string) => { readonly ticket: string; readonly expiresAt: number } | AuthFailure;
    readonly redeemTicket: (ticket: string) => Session | null;
    readonly revoked: (session: Session) => Effect.Effect<void>;
    readonly revoke: (deviceId: string) => Effect.Effect<boolean>;
    readonly setScopes: (deviceId: string, scopes: ReadonlyArray<Scope>) => Effect.Effect<boolean>;
  }
>()("@vitals/gateway/Auth") {}

export const layer = (initialOwner: string | null) =>
  Layer.effect(
    Auth,
    Effect.gen(function* () {
      const store = yield* Store;
      const activity = yield* ActivityLog;
      let owner = initialOwner;
      const tickets = new Map<string, { readonly sessionToken: string; readonly expiresAt: number }>();
      const invalidations = new Map<string, Deferred.Deferred<void>>();
      const versions = new Map<string, number>();
      let epoch = 0;
      const versionOf = (deviceId: string) => `${epoch}:${versions.get(deviceId) ?? 0}`;

      const log = (level: "info" | "warn", kind: string, data: Record<string, unknown>, deviceId: string | null = null) =>
        activity.record({ at: Date.now(), source: "gateway", level, kind, deviceId, data });

      const checkIdentity = (login: string | null): AuthFailure | null => {
        if (owner === null) return { reason: "identity", message: "Owner login is not known yet" };
        if (login !== owner) {
          log("warn", "auth.identity.mismatch", { login });
          return { reason: "identity", message: "This tailnet identity is not allowed" };
        }
        return null;
      };

      const pair = (request: PairRequest, login: string | null): Paired | AuthFailure => {
        const identity = checkIdentity(login);
        if (identity !== null) return identity;
        const result = store.redeemPairing(request.code, request.device, DEFAULT_PAIRED_SCOPES, Date.now());
        if (typeof result === "string") {
          log("warn", "pairing.rejected", { reason: result, device: request.device.name });
          return { reason: "credentials", message: `Pairing code ${result}` };
        }
        log("info", "pairing.consumed", { device: request.device.name, platform: request.device.platform }, result.deviceId);
        return { deviceId: result.deviceId, token: result.token, scopes: DEFAULT_PAIRED_SCOPES, expiresAt: result.expiresAt };
      };

      const issueTicket = (bearer: string) => {
        const now = Date.now();
        const session = store.findSession(bearer, now);
        if (session === null) {
          log("warn", "session.rejected", {});
          return { reason: "credentials" as const, message: "Session is not valid" };
        }
        for (const [key, value] of tickets) if (value.expiresAt < now) tickets.delete(key);
        const ticket = randomToken();
        tickets.set(ticket, { sessionToken: bearer, expiresAt: now + TICKET_TTL_MS });
        return { ticket, expiresAt: now + TICKET_TTL_MS };
      };

      const redeemTicket = (ticket: string): Session | null => {
        const entry = tickets.get(ticket);
        tickets.delete(ticket);
        if (entry === undefined || entry.expiresAt < Date.now()) return null;
        const match = store.findSession(entry.sessionToken, Date.now());
        return match === null ? null : { ...match, version: versionOf(match.device.id) };
      };

      const session = (token: string): SessionInfo | null => {
        const match = store.findSession(token, Date.now());
        if (match === null) return null;
        return { deviceId: match.device.id, scopes: match.device.scopes, pairedAt: match.device.createdAt, expiresAt: match.expiresAt };
      };

      const signal = (deviceId: string) =>
        Effect.gen(function* () {
          versions.set(deviceId, (versions.get(deviceId) ?? 0) + 1);
          const existing = invalidations.get(deviceId);
          if (existing !== undefined) {
            invalidations.delete(deviceId);
            yield* Deferred.succeed(existing, undefined);
          }
        });

      const revoked = (session: Session) =>
        Effect.gen(function* () {
          const deviceId = session.device.id;
          if (versionOf(deviceId) !== session.version) return;
          const existing = invalidations.get(deviceId);
          const waiter = existing ?? (yield* Deferred.make<void>());
          if (existing === undefined) invalidations.set(deviceId, waiter);
          if (versionOf(deviceId) !== session.version) {
            if (existing === undefined && invalidations.get(deviceId) === waiter) invalidations.delete(deviceId);
            return;
          }
          yield* Deferred.await(waiter);
        });

      const setOwnerLogin = (login: string | null) =>
        Effect.gen(function* () {
          const changed = owner !== null && login !== owner;
          owner = login;
          if (!changed) return;
          epoch += 1;
          log("warn", "auth.owner.changed", { login });
          const waiting = [...invalidations.values()];
          invalidations.clear();
          for (const waiter of waiting) yield* Deferred.succeed(waiter, undefined);
        });

      const revoke = (deviceId: string) =>
        Effect.gen(function* () {
          const changed = store.revokeDevice(deviceId, Date.now());
          if (changed) log("info", "session.revoked", {}, deviceId);
          yield* signal(deviceId);
          return changed;
        });

      const unpair = (token: string) =>
        Effect.gen(function* () {
          const match = store.findSession(token, Date.now());
          if (match === null) return false;
          log("info", "device.unpaired", {}, match.device.id);
          return yield* revoke(match.device.id);
        });

      const setScopes = (deviceId: string, scopes: ReadonlyArray<Scope>) =>
        Effect.gen(function* () {
          const changed = store.setScopes(deviceId, scopes);
          if (changed) log("info", "desktop.scope.changed", { scopes }, deviceId);
          yield* signal(deviceId);
          return changed;
        });

      return Auth.of({
        ownerLogin: () => owner,
        setOwnerLogin,
        checkIdentity,
        pair,
        session,
        unpair,
        issueTicket,
        redeemTicket,
        revoked,
        revoke,
        setScopes,
      });
    }),
  );
