import { type KeyPair, fromBase64Url, generateKeyPair, keyPairFromSecret, setRandomSource, toBase64Url } from "@vitals/noise";
import { getRandomBytes } from "expo-crypto";
import * as SecureStore from "expo-secure-store";

import { KEYCHAIN_OPTIONS } from "./credentials";

const KEY = "vitals.remote.device-key";

setRandomSource(getRandomBytes);

let cached: KeyPair | null = null;

export const loadDeviceKey = async (): Promise<KeyPair | null> => {
  if (cached !== null) return cached;
  const stored = await SecureStore.getItemAsync(KEY, KEYCHAIN_OPTIONS);
  if (stored !== null) {
    cached = keyPairFromSecret(fromBase64Url(stored));
    return cached;
  }
  const created = generateKeyPair();
  await SecureStore.setItemAsync(KEY, toBase64Url(created.secretKey), KEYCHAIN_OPTIONS);
  cached = created;
  return created;
};
