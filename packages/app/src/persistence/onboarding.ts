import { Store } from "@vitals/client-runtime";
import * as SecureStore from "expo-secure-store";

import { KEYCHAIN_OPTIONS } from "./credentials";

const KEY = "vitals.remote.onboarded";

export const onboarded = new Store<boolean | null>(null);

void SecureStore.getItemAsync(KEY, KEYCHAIN_OPTIONS)
  .then((value) => onboarded.set(value === "1"))
  .catch(() => onboarded.set(false));

export const finishOnboarding = (): void => {
  onboarded.set(true);
  void SecureStore.setItemAsync(KEY, "1", KEYCHAIN_OPTIONS).catch(() => undefined);
};
