import { type Credentials, decodeCredentials } from "./credentialsSchema.ts";

const KEY = "vitals.remote.credentials";

export const loadCredentials = async (): Promise<Credentials | null> => decodeCredentials(globalThis.localStorage.getItem(KEY));

export const saveCredentials = async (credentials: Credentials): Promise<void> => {
  globalThis.localStorage.setItem(KEY, JSON.stringify(credentials));
};

export const clearCredentials = async (): Promise<void> => {
  globalThis.localStorage.removeItem(KEY);
};
