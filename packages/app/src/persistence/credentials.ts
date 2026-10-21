import { unpair } from "@vitals/client-runtime";
import * as SecureStore from "expo-secure-store";

import { type Credentials, decodeCredentials } from "./credentialsSchema.ts";

const KEY = "vitals.remote.credentials";

export const KEYCHAIN_OPTIONS: SecureStore.SecureStoreOptions = { keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK };

export const loadCredentials = async (): Promise<Credentials | null> =>
  decodeCredentials(await SecureStore.getItemAsync(KEY, KEYCHAIN_OPTIONS));

export const saveCredentials = async (credentials: Credentials): Promise<void> => {
  await SecureStore.setItemAsync(KEY, JSON.stringify(credentials), KEYCHAIN_OPTIONS);
};

export const clearCredentials = async (alreadyRevoked = false): Promise<boolean> => {
  const credentials = await loadCredentials();
  const revoked = alreadyRevoked || credentials === null || (credentials.baseUrl !== null && (await unpair(credentials.baseUrl, credentials.token)));
  await SecureStore.deleteItemAsync(KEY, KEYCHAIN_OPTIONS);
  return revoked;
};
