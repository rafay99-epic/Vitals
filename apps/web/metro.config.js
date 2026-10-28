const path = require("node:path");
const { getDefaultConfig } = require("expo/metro-config");
const { withNativewind } = require("nativewind/metro");

const config = getDefaultConfig(__dirname);
const workspaceRoot = path.resolve(__dirname, "../..");
config.watchFolders = [...new Set([...(config.watchFolders ?? []), workspaceRoot])];

const xterm = require.resolve("@xterm/headless", { paths: [path.join(workspaceRoot, "packages/app")] });
config.resolver.resolveRequest = (context, name, platform) =>
  name === "@xterm/headless" ? { type: "sourceFile", filePath: xterm } : context.resolveRequest(context, name, platform);

module.exports = withNativewind(config);
