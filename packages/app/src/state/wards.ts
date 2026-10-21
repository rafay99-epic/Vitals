import type { ProcessGroupId } from "@vitals/contracts";

export type WardId = Exclude<ProcessGroupId, "protected">;

export const WARD_NAMES: Record<ProcessGroupId, string> = {
  agents: "Agents",
  emulators: "Emulators",
  devServers: "Dev servers",
  browsers: "Browsers",
  other: "Other",
  protected: "Protected",
};

export const WARD_ORDER: ReadonlyArray<WardId> = ["agents", "emulators", "devServers", "browsers", "other"];
