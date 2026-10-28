import fs from "node:fs";
import path from "node:path";

import plugins from "expo/config-plugins";

const { AndroidConfig, IOSConfig, withAndroidManifest, withDangerousMod, withInfoPlist, withXcodeProject } = plugins;

const INSTALL = "android.permission.REQUEST_INSTALL_PACKAGES";
const TILE = "expo.modules.vitalstailnet.DropTileService";
const INTENT_FILE = "VitalsClipboardIntent.swift";

const variant = () => {
  const value = process.env["APP_VARIANT"];
  return value === "stable" || value === "nightly" ? value : "dev";
};

const schemeOf = (config) => {
  const scheme = Array.isArray(config.scheme) ? config.scheme[0] : config.scheme;
  if (typeof scheme !== "string" || scheme.length === 0) throw new Error("@vitals/tailnet: the app config needs a scheme for the Send clipboard shortcut");
  return scheme;
};

const intentSource = (scheme) => `import AppIntents
import UIKit

struct SendClipboardIntent: AppIntent {
  static let title: LocalizedStringResource = "Send clipboard to Mac"
  static let description = IntentDescription("Opens Vitals and sends what you copied to your Mac.")
  static let openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult {
    if let url = URL(string: "${scheme}://clipboard/send") {
      await UIApplication.shared.open(url)
    }
    return .result()
  }
}

struct VitalsShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: SendClipboardIntent(),
      phrases: ["Send clipboard to Mac with \\(.applicationName)", "Send my clipboard with \\(.applicationName)"],
      shortTitle: "Send clipboard",
      systemImageName: "doc.on.clipboard"
    )
  }
}
`;

const withDropAndroid = (config) =>
  withAndroidManifest(config, (mod) => {
    const manifest = mod.modResults.manifest;
    const application = AndroidConfig.Manifest.getMainApplicationOrThrow(mod.modResults);
    const permissions = (manifest["uses-permission"] ?? []).filter((item) => item.$["android:name"] !== INSTALL);
    if (variant() !== "stable") permissions.push({ $: { "android:name": INSTALL } });
    manifest["uses-permission"] = permissions;
    AndroidConfig.Manifest.addMetaDataItemToMainApplication(application, "dev.vitals.drop.SCHEME", schemeOf(config));
    application.service = (application.service ?? []).filter((item) => item.$["android:name"] !== TILE);
    application.service.push({
      $: {
        "android:name": TILE,
        "android:exported": "true",
        "android:label": "Send clipboard",
        "android:icon": "@drawable/vitals_drop_clipboard",
        "android:permission": "android.permission.BIND_QUICK_SETTINGS_TILE",
      },
      "intent-filter": [{ action: [{ $: { "android:name": "android.service.quicksettings.action.QS_TILE" } }] }],
    });
    return mod;
  });

const withDropIos = (config) => {
  const scheme = schemeOf(config);
  const withPlist = withInfoPlist(config, (mod) => {
    mod.modResults["UIFileSharingEnabled"] = true;
    mod.modResults["LSSupportsOpeningDocumentsInPlace"] = true;
    return mod;
  });
  const withSource = withDangerousMod(withPlist, [
    "ios",
    async (mod) => {
      const dir = path.join(mod.modRequest.platformProjectRoot, mod.modRequest.projectName);
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, INTENT_FILE), intentSource(scheme));
      return mod;
    },
  ]);
  return withXcodeProject(withSource, (mod) => {
    const name = mod.modRequest.projectName;
    const filepath = `${name}/${INTENT_FILE}`;
    if (mod.modResults.hasFile(filepath)) return mod;
    const target = IOSConfig.XcodeUtils.getApplicationNativeTarget({ project: mod.modResults, projectName: name });
    IOSConfig.XcodeUtils.addBuildSourceFileToGroup({ filepath, groupName: name, project: mod.modResults, targetUuid: target.uuid });
    return mod;
  });
};

export default (config) => withDropIos(withDropAndroid(config));
