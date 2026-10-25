import { KEYCHAIN_OPTIONS } from "@vitals/app/persistence/credentials.ts";
import * as SecureStore from "expo-secure-store";

const KEY = "vitals.remote.seenCopy";

let seen: string | null = null;

const fingerprint = (text: string): string => {
  let hash = 5381;
  for (let index = 0; index < text.length; index++) hash = ((hash * 33) ^ text.charCodeAt(index)) >>> 0;
  return `${String(text.length)}:${hash.toString(36)}`;
};

void SecureStore.getItemAsync(KEY, KEYCHAIN_OPTIONS)
  .then((value) => {
    seen ??= value;
  })
  .catch(() => undefined);

export const markSeen = (text: string): void => {
  seen = fingerprint(text.trim());
  void SecureStore.setItemAsync(KEY, seen, KEYCHAIN_OPTIONS).catch(() => undefined);
};

export const wasSeen = (text: string): boolean => fingerprint(text.trim()) === seen;
