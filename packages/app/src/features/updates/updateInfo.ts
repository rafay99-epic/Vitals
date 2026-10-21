import * as Updates from "expo-updates";

export interface UpdateInfo {
  readonly channel: string;
  readonly runtime: string;
  readonly running: string;
  readonly createdAt: number | null;
  readonly embedded: boolean;
  readonly launchMs: number | null;
}

export const updateInfo = (): UpdateInfo => ({
  channel: Updates.channel ?? "none",
  runtime: Updates.runtimeVersion ?? "none",
  running: Updates.isEmbeddedLaunch ? "built in" : (Updates.updateId?.slice(0, 8) ?? "none"),
  createdAt: Updates.createdAt?.getTime() ?? null,
  embedded: Updates.isEmbeddedLaunch,
  launchMs: Updates.launchDuration,
});
