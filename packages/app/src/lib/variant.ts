import Constants from "expo-constants";

/** Which of the three phone apps this is (see apps/mobile/app.config.ts): Stable from the stores,
 *  the Nightly beta, or a local Dev build. Each has its own package, so all three can be installed. */
export type Channel = "stable" | "nightly" | "dev";

const variant: unknown = Constants.expoConfig?.extra?.["variant"];

export const channel: Channel = variant === "stable" ? "stable" : variant === "nightly" ? "nightly" : "dev";

/** Only Stable is the store app; Nightly and Dev show the extra tooling (diagnostics). */
export const isStoreBuild = channel === "stable";
