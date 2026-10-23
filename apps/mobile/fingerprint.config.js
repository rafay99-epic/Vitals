// The version changes with every commit (see app.config.ts), so it must not change the runtime,
// or OTA updates would never match an installed build.
const EXPO_CONFIG_VERSIONS = 1;
const RUNTIME_VERSION_IF_STRING = 2;
const ANDROID_AND_IOS_SCRIPTS_IF_NOT_CONTAIN_RUN = 512;
const PACKAGE_JSON_SCRIPTS_ALL = 1024;

module.exports = {
  sourceSkips: EXPO_CONFIG_VERSIONS | RUNTIME_VERSION_IF_STRING | ANDROID_AND_IOS_SCRIPTS_IF_NOT_CONTAIN_RUN | PACKAGE_JSON_SCRIPTS_ALL,
};
