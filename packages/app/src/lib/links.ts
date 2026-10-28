import { Platform } from "react-native";

export const SITE_URL = "https://vitals.rafay99.com";

export const BREW_INSTALL = "brew install --cask rafay99-epic/apps/vitals";

export const TAILSCALE_STORE_URL =
  Platform.OS === "ios" ? "https://apps.apple.com/app/tailscale/id1470499037" : "https://play.google.com/store/apps/details?id=com.tailscale.ipn";
