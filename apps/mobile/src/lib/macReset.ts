import { nearby, macKeyOf } from "@vitals/app/connection/nearby.ts";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { channel } from "@vitals/app/lib/variant.ts";
import { KEYCHAIN_OPTIONS } from "@vitals/app/persistence/credentials.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { Store } from "@vitals/client-runtime";
import * as SecureStore from "expo-secure-store";
import { useEffect } from "react";

const NAME_KEY = "vitals.remote.mac-name";

/** The paired Mac's name, remembered from the last time it answered. */
const macName = new Store<string | null>(null);

void SecureStore.getItemAsync(NAME_KEY, KEYCHAIN_OPTIONS)
  .then((value) => macName.get() === null && macName.set(value))
  .catch(() => undefined);

const remember = (name: string): void => {
  if (macName.get() === name) return;
  macName.set(name);
  void SecureStore.setItemAsync(NAME_KEY, name, KEYCHAIN_OPTIONS).catch(() => undefined);
};

/**
 * The name of the paired Mac when it seems to have been reset: it can't be reached, its key is
 * nowhere on this Wi-Fi, but a Mac with its name advertises a different key. Null otherwise.
 * Only re-pairing fixes that, since a new key is never trusted over Wi-Fi.
 */
export const useMacReset = (): string | null => {
  const remote = useRemote();
  const state = useStore(remote.connection.state);
  const found = useStore(nearby);
  const name = useStore(macName);

  useEffect(() => {
    if (state._tag === "Ready" && state.hello.mac !== null) remember(state.hello.mac.name);
  }, [state]);

  const ours = remote.credentials.macKey ?? null;
  if (state._tag === "Ready" || name === null || ours === null) return null;
  const here = found.filter((mac) => (mac.txt["c"] === "dev") === (channel === "dev"));
  if (here.some((mac) => macKeyOf(mac) === ours)) return null;
  return here.some((mac) => (mac.txt["n"] ?? mac.name) === name && macKeyOf(mac) !== null) ? name : null;
};
