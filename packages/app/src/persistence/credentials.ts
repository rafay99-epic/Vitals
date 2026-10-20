import * as SecureStore from "expo-secure-store";

import { type Credentials, decodeCredentials } from "./credentialsSchema.ts";

const KEY = "vitals.remote.credentials";

export const loadCredentials = async (): Promise<Credentials | null> => decodeCredentials(await SecureStore.getItemAsync(KEY));

export const saveCredentials = async (credentials: Credentials): Promise<void> => {
  await SecureStore.setItemAsync(KEY, JSON.stringify(credentials));
};

export const clearCredentials = async (): Promise<void> => {
  await SecureStore.deleteItemAsync(KEY);
};
