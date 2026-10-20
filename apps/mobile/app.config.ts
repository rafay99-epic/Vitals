import type { ConfigContext, ExpoConfig } from "expo/config";

type Variant = "dev" | "prod";

const variant: Variant = process.env["APP_VARIANT"] === "prod" ? "prod" : "dev";

const PROJECT_ID = "4db0c236-4405-41ad-ad17-dabb1942aa86";

const VARIANTS: Record<Variant, { readonly name: string; readonly suffix: string; readonly scheme: string; readonly channel: string }> = {
  dev: { name: "Vitals Dev", suffix: ".dev", scheme: "vitals-dev", channel: "dev" },
  prod: { name: "Vitals", suffix: "", scheme: "vitals", channel: "production" },
};

const current = VARIANTS[variant];

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

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: current.name,
  slug: "vitals-remote",
  scheme: current.scheme,
  version: "1.0.0",
  icon: "./assets/icon.png",
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
    bundleIdentifier: `com.syntaxlabtechnology.vitals.remote${current.suffix}`,
    supportsTablet: false,
    infoPlist: {
      NSCameraUsageDescription: "Scan the pairing code shown in Vitals on your Mac.",
      NSLocalNetworkUsageDescription: "Connect to your Mac over your tailnet.",
    },
  },
  android: {
    package: `com.syntaxlabtechnology.vitals.remote${current.suffix}`,
    permissions: ["CAMERA", "POST_NOTIFICATIONS", "VIBRATE"],
  },
  plugins: [
    [
      "expo-font",
      {
        ios: { fonts: Object.values(FONTS) },
        android: { fonts: Object.entries(FONTS).map(([fontFamily, path]) => ({ fontFamily, fontDefinitions: [{ path, weight: 400 }] })) },
      },
    ],
    ["expo-camera", { cameraPermission: "Scan the pairing code shown in Vitals on your Mac." }],
    ["expo-notifications", { color: "#ffffff" }],
    "expo-background-task",
    [
      "expo-build-properties",
      {
        android: {
          extraProguardRules: [
            "-keep class * extends androidx.room.RoomDatabase { <init>(); }",
            "-keep class androidx.work.impl.WorkDatabase_Impl { *; }",
            "-keep class * extends androidx.work.InputMerger { <init>(); }",
            "-keep class * extends androidx.work.ListenableWorker { <init>(android.content.Context, androidx.work.WorkerParameters); }",
          ].join("\n"),
        },
      },
    ],
    "expo-secure-store",
    "expo-sqlite",
    "expo-updates",
  ],
  owner: "prometheus99",
  extra: {
    variant,
    eas: { projectId: PROJECT_ID },
  },
});
