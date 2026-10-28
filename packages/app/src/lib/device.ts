import type { DeviceInfo, Platform as WirePlatform } from "@vitals/contracts";
import * as Device from "expo-device";
import { Platform } from "react-native";

import { CLIENT_VERSION } from "../state/remote.ts";

const platform = (): WirePlatform => (Platform.OS === "android" ? "android" : Platform.OS === "ios" ? "ios" : "web");

export const deviceInfo = (): DeviceInfo => {
  const model = (Device.modelName ?? (Platform.OS === "web" ? "Browser" : "Phone")).slice(0, 80);
  const fallback = Platform.OS === "web" ? `Browser on ${Device.osName ?? "web"}` : model;
  return {
    name: (Device.deviceName ?? fallback).slice(0, 80) || "Phone",
    platform: platform(),
    model,
    appVersion: CLIENT_VERSION,
  };
};
