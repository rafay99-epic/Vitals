import type { ConfigContext, ExpoConfig } from "expo/config";
import { type ConfigPlugin, withAppBuildGradle } from "expo/config-plugins";

type Variant = "dev" | "prod";

const variant: Variant = process.env["APP_VARIANT"] === "prod" ? "prod" : "dev";

const PROJECT_ID = "4db0c236-4405-41ad-ad17-dabb1942aa86";

const VARIANTS: Record<Variant, { readonly name: string; readonly suffix: string; readonly scheme: string; readonly channel: string; readonly art: string }> = {
  dev: { name: "Vitals Dev", suffix: ".dev", scheme: "vitals-dev", channel: "dev", art: "-dev" },
  prod: { name: "Vitals", suffix: "", scheme: "vitals", channel: "production", art: "" },
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
  version: "1.0.0",
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
    bundleIdentifier: `com.syntaxlabtechnology.vitals.remote${current.suffix}`,
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
    package: `com.syntaxlabtechnology.vitals.remote${current.suffix}`,
    permissions: ["CAMERA", "POST_NOTIFICATIONS", "VIBRATE", "ACCESS_LOCAL_NETWORK"],
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

export default (context: ConfigContext): ExpoConfig => withUploadSigning(app(context));
