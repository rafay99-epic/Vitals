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

const FOCUS_WAIT_MS = 250;
const FOCUS_TRIES = 8;

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

type Copied = { readonly _tag: "Image"; readonly data: string } | { readonly _tag: "Text"; readonly text: string };

const readCopied = async (): Promise<Copied | null> => {
  if (await Clipboard.hasImageAsync().catch(() => false)) {
    const image = await Clipboard.getImageAsync({ format: "png" }).catch(() => null);
    if (image !== null) return { _tag: "Image", data: image.data };
  }
  const text = (await Clipboard.getStringAsync().catch(() => "")).trim();
  return text === "" ? null : { _tag: "Text", text };
};

export const sendClipboardNow = async (remote: Remote): Promise<void> => {
  let copied: Copied | null = null;
  for (let attempt = 0; attempt < FOCUS_TRIES && copied === null; attempt += 1) {
    await wait(FOCUS_WAIT_MS);
    copied = await readCopied();
  }
  if (copied === null) return toast.show("Nothing to send. Copy something first.");
  if (copied._tag === "Image") await sendPastedImage(remote, copied.data, "Sent to your Mac");
  else await sendText(remote, copied.text, "Sent to your Mac");
};
