import type { ConfigContext, ExpoConfig } from "expo/config";

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: "Vitals",
  slug: "vitals-web",
  version: "1.0.0",
  userInterfaceStyle: "dark",
  backgroundColor: "#000000",
  platforms: ["web"],
  experiments: { reactCompiler: true },
  web: { bundler: "metro", output: "single", backgroundColor: "#000000", favicon: "./public/favicon.png" },
});
