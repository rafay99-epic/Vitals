import { Store } from "@vitals/client-runtime";
import { channel } from "@vitals/app/lib/variant.ts";
import * as Application from "expo-application";
import { Platform } from "react-native";

/** The rolling pre-release that always holds the newest Nightly APK (scripts/release-nightly.sh).
 *  Its title carries "build <n>", the APK's versionCode, which is how builds are ordered. */
const RELEASE_URL = "https://api.github.com/repos/rafay99-epic/Vitals/releases/tags/android-nightly";
const NIGHTLY_APK = "Vitals-Nightly.apk";

export type NightlyState =
  | { readonly _tag: "Unchecked" }
  | { readonly _tag: "Current" }
  | { readonly _tag: "Available"; readonly build: number; readonly url: string }
  | { readonly _tag: "Unavailable"; readonly reason: string };

/** Only the Android Nightly app updates itself from GitHub; Stable uses Google Play. */
export const nightlySupported = Platform.OS === "android" && channel === "nightly";

export const nightlyState = new Store<NightlyState>({ _tag: "Unchecked" });

/** The versionCode of the installed APK. Read natively: OTA updates replace the JS config, not this. */
export const installedBuild = Number(Application.nativeBuildVersion ?? 0);

interface Release {
  readonly name: string;
  readonly assets: ReadonlyArray<{ readonly name: string; readonly browser_download_url: string }>;
}

const isRelease = (value: unknown): value is Release =>
  typeof value === "object" &&
  value !== null &&
  "name" in value &&
  typeof value.name === "string" &&
  "assets" in value &&
  Array.isArray(value.assets) &&
  value.assets.every((asset: unknown) => typeof asset === "object" && asset !== null && "name" in asset && typeof asset.name === "string" && "browser_download_url" in asset && typeof asset.browser_download_url === "string");

/** Looks for a newer Nightly APK. Native changes need a new install; everything else arrives over the air. */
export const checkNightly = async (): Promise<void> => {
  if (!nightlySupported) return;
  try {
    const response = await fetch(RELEASE_URL, { headers: { Accept: "application/vnd.github+json" } });
    if (!response.ok) throw new Error(response.status === 404 ? "no Nightly build published yet" : `GitHub returned ${String(response.status)}`);
    const release: unknown = await response.json();
    const apk = isRelease(release) ? release.assets.find((asset) => asset.name === NIGHTLY_APK) : undefined;
    const build = isRelease(release) ? Number(/build (\d+)/.exec(release.name)?.[1] ?? 0) : 0;
    if (apk === undefined || build === 0) throw new Error("the Nightly release has no APK");
    nightlyState.set(build > installedBuild ? { _tag: "Available", build, url: apk.browser_download_url } : { _tag: "Current" });
  } catch (error) {
    nightlyState.set({ _tag: "Unavailable", reason: error instanceof Error ? error.message : "could not reach GitHub" });
  }
};
