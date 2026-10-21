import type { UpdateInfo } from "./updateInfo.ts";

export const updateInfo = (): UpdateInfo => ({
  channel: "web",
  runtime: "served by the Mac",
  running: "built in",
  createdAt: null,
  embedded: true,
  launchMs: null,
});
