import { Store } from "@vitals/client-runtime";
import * as Data from "effect/Data";
import * as Effect from "effect/Effect";
import * as Schedule from "effect/Schedule";
import * as Network from "expo-network";
import * as Updates from "expo-updates";

export type UpdatePhase =
  | { readonly _tag: "Idle" }
  | { readonly _tag: "Checking"; readonly blocking: boolean }
  | { readonly _tag: "Downloading"; readonly publishedAt: number | null }
  | { readonly _tag: "Restarting"; readonly publishedAt: number | null }
  | { readonly _tag: "Current"; readonly at: number }
  | { readonly _tag: "Offline"; readonly at: number; readonly reason: string };

class UpdateFailed extends Data.TaggedError("UpdateFailed")<{ readonly step: string; readonly message: string }> {}

export const updatesEnabled = !__DEV__ && Updates.isEnabled;

export const updatePhase = new Store<UpdatePhase>(updatesEnabled ? { _tag: "Checking", blocking: true } : { _tag: "Idle" });

const step = <A>(name: string, run: () => Promise<A>) =>
  Effect.tryPromise({ try: run, catch: (error) => new UpdateFailed({ step: name, message: error instanceof Error ? error.message : String(error) }) });

const publishedAt = (manifest: Updates.Manifest | undefined): number | null => {
  const created = manifest !== undefined && "createdAt" in manifest ? Date.parse(String(manifest.createdAt)) : Number.NaN;
  return Number.isFinite(created) ? created : null;
};

const reachable = step("network", Network.getNetworkStateAsync).pipe(
  Effect.flatMap((state) => (state.isInternetReachable === false ? Effect.fail(new UpdateFailed({ step: "network", message: "No internet" })) : Effect.void)),
);

const restart = (published: number | null) =>
  Effect.gen(function* () {
    updatePhase.set({ _tag: "Restarting", publishedAt: published });
    yield* step("restart", () => Updates.reloadAsync());
  });

const download = (published: number | null) =>
  Effect.gen(function* () {
    updatePhase.set({ _tag: "Downloading", publishedAt: published });
    const fetched = yield* step("download", Updates.fetchUpdateAsync).pipe(
      Effect.timeout("90 seconds"),
      Effect.retry({ schedule: Schedule.exponential("1 second"), times: 2 }),
    );
    if (!fetched.isNew && !fetched.isRollBackToEmbedded) return;
    yield* restart(published);
  });

const check = (blocking: boolean) =>
  Effect.gen(function* () {
    updatePhase.set({ _tag: "Checking", blocking });
    yield* reachable;
    const result = yield* step("check", Updates.checkForUpdateAsync).pipe(
      Effect.timeout(blocking ? "4 seconds" : "8 seconds"),
      Effect.retry({ schedule: Schedule.exponential("500 millis"), times: blocking ? 0 : 1 }),
    );
    if (result.isAvailable || result.isRollBackToEmbedded) yield* download(publishedAt(result.manifest));
  });

let running: Promise<void> | null = null;

export const checkForUpdate = (blocking: boolean): Promise<void> => {
  if (!updatesEnabled) return Promise.resolve();
  running ??= Effect.runPromise(
    check(blocking).pipe(
      Effect.match({
        onSuccess: () => updatePhase.set({ _tag: "Current", at: Date.now() }),
        onFailure: (error) => updatePhase.set({ _tag: "Offline", at: Date.now(), reason: error._tag === "UpdateFailed" ? `${error.step}: ${error.message}` : "Timed out" }),
      }),
    ),
  ).finally(() => {
    running = null;
  });
  return running;
};

export const isBlocking = (phase: UpdatePhase): boolean =>
  (phase._tag === "Checking" && phase.blocking) || phase._tag === "Downloading" || phase._tag === "Restarting";
