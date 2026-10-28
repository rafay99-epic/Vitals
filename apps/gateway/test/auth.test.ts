import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";

import * as ActivityLog from "../src/activity/ActivityLog.ts";
import { Auth, layer as authLayer } from "../src/auth/Auth.ts";
import { ACTIVITY_MIGRATIONS, REMOTE_MIGRATIONS } from "../src/persistence/migrations.ts";
import { openDatabase } from "../src/persistence/sqlite.ts";
import { Store, layer as storeLayer } from "../src/persistence/Store.ts";

const OWNER = "owner@example.com";

const withAuth = async <A>(body: Effect.Effect<A, never, Auth | Store>) => {
  const dir = mkdtempSync(join(tmpdir(), "vitals-auth-"));
  const core = Layer.mergeAll(
    storeLayer(openDatabase(join(dir, "remote.db"), REMOTE_MIGRATIONS)),
    ActivityLog.layer(openDatabase(join(dir, "activity.db"), ACTIVITY_MIGRATIONS)),
  );
  try {
    return await Effect.runPromise(Effect.scoped(body.pipe(Effect.provide(authLayer(OWNER).pipe(Layer.provideMerge(core))))));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

const openSession = Effect.gen(function* () {
  const auth = yield* Auth;
  const store = yield* Store;
  const { code } = store.createPairing(Date.now());
  const paired = auth.pair({ code, device: { name: "Phone", platform: "android", model: "P", appVersion: "1" } }, OWNER);
  if ("reason" in paired) return yield* Effect.die(paired.message);
  const ticket = auth.issueTicket(paired.token);
  if ("reason" in ticket) return yield* Effect.die(ticket.message);
  const session = auth.redeemTicket(ticket.ticket);
  if (session === null) return yield* Effect.die("no session");
  return session;
});

const settles = <A, E, R>(effect: Effect.Effect<A, E, R>) =>
  effect.pipe(
    Effect.as("settled" as const),
    Effect.timeoutOrElse({ duration: "500 millis", orElse: () => Effect.succeed("waiting" as const) }),
  );

describe("auth invalidation", () => {
  test("a revoke that lands before the socket starts watching still ends it", async () => {
    const outcome = await withAuth(
      Effect.gen(function* () {
        const auth = yield* Auth;
        const session = yield* openSession;
        yield* auth.revoke(session.device.id);
        return yield* settles(auth.revoked(session));
      }),
    );
    expect(outcome).toBe("settled");
  });

  test("an untouched session keeps waiting", async () => {
    const outcome = await withAuth(
      Effect.gen(function* () {
        const auth = yield* Auth;
        const session = yield* openSession;
        return yield* settles(auth.revoked(session));
      }),
    );
    expect(outcome).toBe("waiting");
  });

  test("a new tailnet owner drops sockets opened by the previous one", async () => {
    const outcome = await withAuth(
      Effect.gen(function* () {
        const auth = yield* Auth;
        const session = yield* openSession;
        yield* auth.setOwnerLogin("someone-else@example.com");
        return yield* settles(auth.revoked(session));
      }),
    );
    expect(outcome).toBe("settled");
  });
});
