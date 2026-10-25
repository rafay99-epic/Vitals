import { type AdminResult, FS_LIMITS } from "@vitals/contracts";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

import { ActivityLog } from "../activity/ActivityLog.ts";
import { Auth } from "../auth/Auth.ts";
import { Bridge, type AdminHandler } from "../bridge/Bridge.ts";
import { FsService } from "../fs/FsService.ts";
import { Lan } from "../lan/Lan.ts";
import { Store } from "../persistence/Store.ts";
import { Serve } from "../tailscale/Serve.ts";
import { Connections } from "../ws/Connections.ts";

export const layer = Layer.effectDiscard(
  Effect.gen(function* () {
    const bridge = yield* Bridge;
    const store = yield* Store;
    const auth = yield* Auth;
    const serve = yield* Serve;
    const connections = yield* Connections;
    const activity = yield* ActivityLog;
    const lan = yield* Lan;
    const files = yield* FsService;

    const handle: AdminHandler = (op) =>
      Effect.gen(function* () {
        switch (op._tag) {
          case "CreatePairing": {
            const { code, expiresAt } = store.createPairing(Date.now());
            const status = yield* serve.status;
            activity.record({ at: Date.now(), source: "desktop", level: "info", kind: "pairing.created", data: { expiresAt } });
            return {
              _tag: "CreatePairing",
              code,
              url: status.url === null ? null : `${status.url}/pair#code=${code}${lan.info === null ? "" : `&key=${lan.info.key}`}`,
              expiresAt,
            } satisfies AdminResult;
          }
          case "ListDevices": {
            const connected = yield* connections.connectedDevices;
            return {
              _tag: "ListDevices",
              devices: store.devices().map((device) => ({ ...device, connected: connected.has(device.id) })),
            } satisfies AdminResult;
          }
          case "RevokeDevice": {
            const changed = yield* auth.revoke(op.deviceId);
            if (!changed) return yield* Effect.fail("unknown device");
            activity.record({ at: Date.now(), source: "desktop", level: "info", kind: "desktop.device.revoked", deviceId: op.deviceId, data: {} });
            return { _tag: "RevokeDevice" } satisfies AdminResult;
          }
          case "SetScopes": {
            const changed = yield* auth.setScopes(op.deviceId, op.scopes);
            if (!changed) return yield* Effect.fail("unknown device");
            return { _tag: "SetScopes" } satisfies AdminResult;
          }
          case "ResolvePairPrompt": {
            if (!lan.resolvePrompt(op.id, op.allow)) return yield* Effect.fail("that request has ended");
            return { _tag: "ResolvePairPrompt" } satisfies AdminResult;
          }
          case "FsDevices": {
            const { devices } = yield* files.devices(null);
            return { _tag: "FsDevices", devices } satisfies AdminResult;
          }
          case "FsRoots": {
            const { roots } = yield* files.roots({ device: op.device }, false).pipe(Effect.mapError((error) => error.message));
            return { _tag: "FsRoots", roots } satisfies AdminResult;
          }
          case "FsList": {
            const result = yield* files.list({ device: op.device, path: op.path, sort: "name", hidden: false, offset: op.offset, limit: FS_LIMITS.page }).pipe(Effect.mapError((error) => error.message));
            return { _tag: "FsList", result } satisfies AdminResult;
          }
          case "FsThumbs": {
            const { thumbs } = yield* files.thumbs({ device: op.device, paths: op.paths }).pipe(Effect.mapError((error) => error.message));
            return { _tag: "FsThumbs", thumbs } satisfies AdminResult;
          }
          case "FsPull": {
            const { files: count } = yield* files.pull(null, { device: op.device, paths: op.paths }).pipe(Effect.mapError((error) => error.message));
            return { _tag: "FsPull", files: count } satisfies AdminResult;
          }
        }
      });

    yield* bridge.serveAdmin(handle).pipe(Effect.forkScoped);
  }),
);
