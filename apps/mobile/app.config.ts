import { execFileSync } from "node:child_process";

import type { ConfigContext, ExpoConfig } from "expo/config";
import { type ConfigPlugin, withAppBuildGradle } from "expo/config-plugins";

/**
 * Three apps, like the Mac's channels (`VITALS_CHANNEL`), installable side by side:
 * Stable ships to the stores from `main`, Nightly is the beta built from `nightly` and handed out
 * as an APK, and Dev is local only. APP_VARIANT picks one; anything else builds Dev.
 */
type Variant = "stable" | "nightly" | "dev";

const variant: Variant = process.env["APP_VARIANT"] === "stable" ? "stable" : process.env["APP_VARIANT"] === "nightly" ? "nightly" : "dev";

const PROJECT_ID = "4db0c236-4405-41ad-ad17-dabb1942aa86";

const VARIANTS: Record<Variant, { readonly name: string; readonly suffix: string; readonly scheme: string; readonly channel: string; readonly art: string }> = {
  stable: { name: "Vitals", suffix: "", scheme: "vitals", channel: "production", art: "" },
  nightly: { name: "Vitals Nightly", suffix: ".nightly", scheme: "vitals-nightly", channel: "nightly", art: "-nightly" },
  dev: { name: "Vitals Dev", suffix: ".dev", scheme: "vitals-dev", channel: "dev", art: "-dev" },
};

const current = VARIANTS[variant];

/**
 * The same scheme as the Mac app: version `0.<commit count>`, and the count itself is the Android
 * versionCode and iOS build number, so each build orders after the last. Each app counts its own
 * branch (Stable `main`, Nightly `nightly`), and each branch's count only grows. CI can pin it
 * with VITALS_COMMIT_COUNT. A shallow clone counts too few commits, so Stable and Nightly refuse
 * one rather than ship a wrong number; Dev builds and tooling just get 0.
 */
const commitCount = (): number => {
  const pinned = process.env["VITALS_COMMIT_COUNT"];
  const git = (...args: ReadonlyArray<string>) => execFileSync("git", args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  try {
    if (pinned === undefined && git("rev-parse", "--is-shallow-repository") === "true") throw new Error("shallow clone");
    const count = Number(pinned ?? git("rev-list", "--count", "HEAD"));
    if (!Number.isInteger(count) || count < 1) throw new Error(`not a commit count: ${String(pinned)}`);
    return count;
  } catch (cause) {
    if (variant !== "dev") throw new Error("Vitals Remote: Stable and Nightly builds take their version from the full git history. Build from a full clone or set VITALS_COMMIT_COUNT.", { cause });
    return 0;
  }
};

const commits = commitCount();

const bundleId = `com.syntaxlabtechnology.vitals.remote${current.suffix}`;

/** Everything people share into Vitals from other apps, sent on to the Mac. */
const SHARE_TYPES = ["text/*", "image/*", "video/*", "audio/*", "application/*"];

const FONT_ROOT = "../../packages/ui/node_modules/@expo-google-fonts";

const FONTS: Record<string, string> = {
  "InstrumentSerif-Regular": `${FONT_ROOT}/instrument-serif/400Regular/InstrumentSerif_400Regular.ttf`,
  "InstrumentSerif-Italic": `${FONT_ROOT}/instrument-serif/400Regular_Italic/InstrumentSerif_400Regular_Italic.ttf`,
  "Geist-Regular": `${FONT_ROOT}/geist/400Regular/Geist_400Regular.ttf`,
  "Geist-Medium": `${FONT_ROOT}/geist/500Medium/Geist_500Medium.ttf`,
  "Geist-SemiBold": `${FONT_ROOT}/geist/600SemiBold/Geist_600SemiBold.ttf`,
  "GeistMono-Regular": `${FONT_ROOT}/geist-mono/400Regular/GeistMono_400Regular.ttf`,
  "GeistMono-Medium": `${FONT_ROOT}/geist-mono/500Medium/GeistMono_500Medium.ttf`,
};

const UPLOAD_SIGNING = `
if (findProperty('VITALS_UPLOAD_STORE_FILE')) {
    android {
        signingConfigs {
            upload {
                storeFile file(findProperty('VITALS_UPLOAD_STORE_FILE'))
                storePassword findProperty('VITALS_UPLOAD_STORE_PASSWORD')
                keyAlias findProperty('VITALS_UPLOAD_KEY_ALIAS')
                keyPassword findProperty('VITALS_UPLOAD_KEY_PASSWORD')
            }
        }
        buildTypes {
            release {
                signingConfig signingConfigs.upload
            }
        }
    }
}
`;

const withUploadSigning: ConfigPlugin = (config) =>
  withAppBuildGradle(config, (gradle) => {
    if (!gradle.modResults.contents.includes("VITALS_UPLOAD_STORE_FILE")) gradle.modResults.contents += UPLOAD_SIGNING;
    return gradle;
  });

const app = ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: current.name,
  slug: "vitals-remote",
  scheme: current.scheme,
  version: `0.${String(commits)}`,
  icon: `./assets/icon${current.art}.png`,
  orientation: "portrait",
  userInterfaceStyle: "dark",
  backgroundColor: "#000000",
  platforms: ["ios", "android"],
  experiments: { reactCompiler: true },
  runtimeVersion: { policy: "fingerprint" },
  updates: {
    enabled: true,
    url: `https://u.expo.dev/${PROJECT_ID}`,
    checkAutomatically: "NEVER",
    fallbackToCacheTimeout: 0,
    requestHeaders: { "expo-channel-name": current.channel },
  },
  ios: {
    bundleIdentifier: bundleId,
    buildNumber: String(commits),
    supportsTablet: false,
    icon: {
      light: `./assets/icon${current.art}.png`,
      dark: `./assets/icon-dark${current.art}.png`,
      tinted: `./assets/icon-tinted${current.art}.png`,
    },
    infoPlist: {
      NSCameraUsageDescription: "Scan the pairing code shown in Vitals on your Mac.",
      NSLocalNetworkUsageDescription: "Find and connect to Vitals on your Mac over Wi-Fi.",
      NSBonjourServices: ["_vitals._tcp"],
      NSAppTransportSecurity: { NSAllowsLocalNetworking: true },
    },
  },
  android: {
    package: bundleId,
    versionCode: commits,
    permissions: ["CAMERA", "POST_NOTIFICATIONS", "VIBRATE", "ACCESS_LOCAL_NETWORK", "MANAGE_EXTERNAL_STORAGE", "READ_EXTERNAL_STORAGE"],
    adaptiveIcon: {
      foregroundImage: `./assets/adaptive-foreground${current.art}.png`,
      monochromeImage: `./assets/adaptive-monochrome${current.art}.png`,
      backgroundColor: "#000000",
    },
  },
  plugins: [
    [
      "expo-font",
      {
        ios: { fonts: Object.values(FONTS) },
        android: { fonts: Object.entries(FONTS).map(([fontFamily, path]) => ({ fontFamily, fontDefinitions: [{ path, weight: 400 }] })) },
      },
    ],
    [
      "expo-splash-screen",
      {
        image: "./assets/splash.png",
        imageWidth: 96,
        resizeMode: "contain",
        backgroundColor: "#000000",
        dark: { image: "./assets/splash.png", backgroundColor: "#000000" },
      },
    ],
    ["expo-camera", { cameraPermission: "Scan the pairing code shown in Vitals on your Mac." }],
    ["expo-notifications", { icon: "./assets/notification-icon.png", color: "#5cf2a6" }],
    "expo-background-task",
    [
      "expo-build-properties",
      {
        android: {
          usesCleartextTraffic: true,
          extraProguardRules: [
            "-keep class * extends androidx.room.RoomDatabase { <init>(); }",
            "-keep class androidx.work.impl.WorkDatabase_Impl { *; }",
            "-keep class * extends androidx.work.InputMerger { <init>(); }",
            "-keep class * extends androidx.work.ListenableWorker { <init>(android.content.Context, androidx.work.WorkerParameters); }",
          ].join("\n"),
        },
      },
    ],
    ["expo-image-picker", { photosPermission: "Pick photos and videos to send to your Mac.", cameraPermission: false, microphonePermission: false }],
    ["expo-media-library", { photosPermission: false, savePhotosPermission: "Save photos and videos from your Mac to Photos.", granularPermissions: ["photo", "video"] }],
    [
      "expo-sharing",
      {
        // The share extension and the app trade shared items through an App Group, one per app.
        ios: {
          enabled: true,
          appGroupId: `group.${bundleId}`,
          activationRule: { supportsText: true, supportsWebUrlWithMaxCount: 1, supportsImageWithMaxCount: 20, supportsMovieWithMaxCount: 20, supportsFileWithMaxCount: 20 },
        },
        android: { enabled: true, singleShareMimeTypes: SHARE_TYPES, multipleShareMimeTypes: SHARE_TYPES },
      },
    ],
    "expo-secure-store",
    "expo-sqlite",
    "expo-updates",
    "@vitals/tailnet/app.plugin.js",
  ],
  owner: "prometheus99",
  extra: {
    variant,
    eas: { projectId: PROJECT_ID },
  },
});

export default (context: ConfigContext): ExpoConfig => withUploadSigning(app(context));
