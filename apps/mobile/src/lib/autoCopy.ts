import { Store } from "@vitals/client-runtime";
import { KEYCHAIN_OPTIONS } from "@vitals/app/persistence/credentials.ts";
import * as SecureStore from "expo-secure-store";

const KEY = "vitals.remote.autoCopy";

/** "Copy Mac copies here": each new Mac copy lands on this phone's clipboard while Vitals is open. Off by default. */
export const autoCopy = new Store<boolean>(false);
let changed = false;

void SecureStore.getItemAsync(KEY, KEYCHAIN_OPTIONS)
  .then((value) => changed || autoCopy.set(value === "1"))
  .catch(() => undefined);

export const setAutoCopy = (on: boolean): void => {
  changed = true;
  autoCopy.set(on);
  void SecureStore.setItemAsync(KEY, on ? "1" : "0", KEYCHAIN_OPTIONS).catch(() => undefined);
};
