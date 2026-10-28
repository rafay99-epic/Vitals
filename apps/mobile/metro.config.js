const path = require("node:path");
const { getSentryExpoConfig } = require("@sentry/react-native/metro");
const { withNativewind } = require("nativewind/metro");

// Expo's default config plus debug ids in each bundle, so Sentry can match uploaded source maps.
const config = getSentryExpoConfig(__dirname);
const workspaceRoot = path.resolve(__dirname, "../..");
config.watchFolders = [...new Set([...(config.watchFolders ?? []), workspaceRoot])];

module.exports = withNativewind(config);
