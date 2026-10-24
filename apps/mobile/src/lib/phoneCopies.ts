import { Store } from "@vitals/client-runtime";
import { KEYCHAIN_OPTIONS } from "@vitals/app/persistence/credentials.ts";
import type { Remote } from "@vitals/app/state/remote.ts";
import * as Clipboard from "expo-clipboard";
import * as SecureStore from "expo-secure-store";

import { toast } from "../ui/Toast.tsx";
import { batchOf, pastedImage, sendBatch, textItem } from "./clips.ts";
import { markSeen, wasSeen } from "./seenCopy.ts";

const SEND_KEY = "vitals.remote.sendCopies";

export type PhoneCopy = { readonly _tag: "Text"; readonly text: string } | { readonly _tag: "Unread" };

export const sendCopies = new Store<boolean>(false);
export const phoneCopy = new Store<PhoneCopy | null>(null);

let sendChanged = false;

void SecureStore.getItemAsync(SEND_KEY, KEYCHAIN_OPTIONS)
  .then((value) => sendChanged || sendCopies.set(value === "1"))
  .catch(() => undefined);

export const setSendCopies = (on: boolean): void => {
  sendChanged = true;
  sendCopies.set(on);
  void SecureStore.setItemAsync(SEND_KEY, on ? "1" : "0", KEYCHAIN_OPTIONS).catch(() => undefined);
};

const canOperate = (remote: Remote): boolean => {
  const state = remote.connection.state.get();
  return (state._tag === "Ready" ? state.hello.scopes : remote.credentials.scopes).includes("operate");
};

export const sendText = async (remote: Remote, text: string, done: string): Promise<boolean> => {
  markSeen(text);
  phoneCopy.set(null);
  return sendBatch(remote, batchOf([textItem(text)], "copied on this phone"), "clipboard", done);
};

export const sendPastedImage = async (remote: Remote, dataUri: string, done: string): Promise<boolean> => {
  phoneCopy.set(null);
  return sendBatch(remote, batchOf([pastedImage(dataUri)], "copied on this phone"), "clipboard", done);
};

export const checkPhoneCopy = async (remote: Remote, canRead: boolean): Promise<void> => {
  if (!canOperate(remote)) return;
  if (!canRead) {
    if (sendCopies.get() && (await Clipboard.hasStringAsync())) phoneCopy.set({ _tag: "Unread" });
    return;
  }
  const text = (await Clipboard.getStringAsync().catch(() => "")).trim();
  if (text === "" || wasSeen(text)) return;
  markSeen(text);
  if (sendCopies.get()) {
    await sendText(remote, text, "On your Mac's clipboard. Paste with ⌘V.");
    return;
  }
  phoneCopy.set({ _tag: "Text", text });
};

const IN_FRONT_MS = 300;

export const sendClipboardNow = async (remote: Remote): Promise<void> => {
  await new Promise((resolve) => setTimeout(resolve, IN_FRONT_MS));
  if (await Clipboard.hasImageAsync().catch(() => false)) {
    const image = await Clipboard.getImageAsync({ format: "png" }).catch(() => null);
    if (image !== null) {
      await sendPastedImage(remote, image.data, "Sent to your Mac");
      return;
    }
  }
  const text = (await Clipboard.getStringAsync().catch(() => "")).trim();
  if (text === "") return toast.show("Nothing to send. Copy something first.");
  await sendText(remote, text, "Sent to your Mac");
};
