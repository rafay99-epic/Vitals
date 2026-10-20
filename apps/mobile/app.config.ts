import type { ConfigContext, ExpoConfig } from "expo/config";

type Variant = "dev" | "preview" | "prod";

const variant: Variant = process.env["APP_VARIANT"] === "prod" ? "prod" : process.env["APP_VARIANT"] === "preview" ? "preview" : "dev";

const suffix: Record<Variant, string> = { dev: ".dev", preview: ".preview", prod: "" };
const names: Record<Variant, string> = { dev: "Vitals Dev", preview: "Vitals Preview", prod: "Vitals" };

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: names[variant],
  slug: "vitals-remote",
  scheme: `vitals${variant === "prod" ? "" : `-${variant}`}`,
  version: "1.0.0",
  icon: "./assets/icon.png",
  orientation: "portrait",
  userInterfaceStyle: "dark",
  backgroundColor: "#000000",
  platforms: ["ios", "android"],
  experiments: { reactCompiler: true },
  ios: {
    bundleIdentifier: `com.syntaxlabtechnology.vitals.remote${suffix[variant]}`,
    supportsTablet: false,
    infoPlist: {
      NSCameraUsageDescription: "Scan the pairing code shown in Vitals on your Mac.",
      NSLocalNetworkUsageDescription: "Connect to your Mac over your tailnet.",
    },
  },
  android: {
    package: `com.syntaxlabtechnology.vitals.remote${suffix[variant]}`,
    permissions: ["CAMERA", "POST_NOTIFICATIONS", "VIBRATE"],
  },
  plugins: [
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
            "-keep class androidx.work.** { *; }",
          ].join("\n"),
        },
      },
    ],
    "expo-secure-store",
    "expo-sqlite",
  ],
  owner: "prometheus99",
  extra: {
    variant,
    eas: { projectId: "4db0c236-4405-41ad-ad17-dabb1942aa86" },
  },
});
