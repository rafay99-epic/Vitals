import { NativeModule, requireOptionalNativeModule } from "expo";

/** What Play knows about a newer build. `version` is its versionCode. */
export interface PlayFacts {
  readonly available: boolean;
  readonly version: number;
  readonly immediate: boolean;
  readonly flexible: boolean;
  readonly download: "idle" | "downloading" | "downloaded";
}

export type PlayOutcome = "accepted" | "cancelled" | "failed";

/** Why a Play download stopped: `blocked` is Android holding it for battery or storage. */
export type PlayStop = "download" | "blocked" | "cancelled";

type Events = {
  onProgress: (event: { readonly progress: number }) => void;
  onDownloaded: () => void;
  onStopped: (event: { readonly reason: PlayStop }) => void;
};

declare class VitalsUpdateModule extends NativeModule<Events> {
  check(): Promise<PlayFacts | null>;
  start(immediate: boolean): Promise<PlayOutcome | null>;
  complete(): void;
}

// Null on iOS: every call below is then a no-op.
const native = requireOptionalNativeModule<VitalsUpdateModule>("VitalsUpdate");

export const playModule = native !== null;

export const checkPlayStore = async (): Promise<PlayFacts | null> => (await native?.check()) ?? null;

/** Opens Play's own update screen. Null when Play has nothing to start. */
export const startPlayStore = async (immediate: boolean): Promise<PlayOutcome | null> => (await native?.start(immediate)) ?? null;

/** Installs a downloaded flexible update. The app closes and Play reopens it. */
export const completePlayStore = (): void => native?.complete();

export const onPlayStore = (on: Events): { readonly remove: () => void } => {
  if (native === null) return { remove: () => undefined };
  const subscriptions = [native.addListener("onProgress", on.onProgress), native.addListener("onDownloaded", on.onDownloaded), native.addListener("onStopped", on.onStopped)];
  return { remove: () => subscriptions.forEach((subscription) => subscription.remove()) };
};
