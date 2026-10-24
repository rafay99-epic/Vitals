import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { clipTitle } from "@vitals/app/features/clips/format.ts";
import { type ResolvedSharePayload, type SharePayload, useIncomingShare } from "expo-sharing";
import { useEffect, useRef } from "react";
import { AppState } from "react-native";

import { autoCopy } from "./lib/autoCopy.ts";
import { batchOf, copyToPhone, nameFromUri, type Picked, textItem } from "./lib/clips.ts";
import { openClipboard } from "./navigation.ts";
import { sendSheet } from "./sheets/ClipSheets.tsx";
import { sheet, toast } from "./ui/index.ts";

const SHORT = 26;

const short = (text: string): string => (text.length > SHORT ? `${text.slice(0, SHORT)}…` : text);

/** While Vitals is open and the switch is on, each new Mac copy lands on this phone's clipboard. */
function useAutoCopy() {
  const remote = useRemote();
  useEffect(
    () =>
      remote.clips.onAdded((clip) => {
        if (!autoCopy.get() || clip.deviceId !== null || AppState.currentState !== "active") return;
        if (clip.kind !== "text" && clip.kind !== "link" && clip.kind !== "image") return;
        void copyToPhone(remote, clip).then((copied) => {
          if (!copied) return;
          toast.show(clip.kind === "image" ? "Mac image is on this phone's clipboard" : `Mac copy is on this phone: ${short(clipTitle(clip))}`);
        });
      }),
    [remote],
  );
}

/** A resolved share payload as something to send. Web pages arrive as their link. */
const pickedOf = (payload: ResolvedSharePayload): Picked | null => {
  if (payload.contentType === "text" || payload.contentType === undefined || payload.contentType === null) return payload.value === "" ? null : textItem(payload.value);
  if (payload.contentType === "website") return textItem(payload.value);
  const uri = payload.contentUri;
  if (uri === null) return null;
  const kind = payload.contentType === "image" ? "image" : "file";
  return {
    kind,
    uri,
    name: payload.originalName ?? nameFromUri(uri, kind, payload.contentMimeType),
    mime: payload.contentMimeType,
    size: payload.contentSize ?? 0,
  };
};

/** If resolving fails, fall back to the raw payload: text and links still go through. */
const rawPickedOf = (payload: SharePayload): Picked | null => {
  if (payload.shareType === "text" || payload.shareType === "url") return payload.value === "" ? null : textItem(payload.value);
  if (payload.value === "") return null;
  const kind = payload.shareType === "image" ? "image" : "file";
  return { kind, uri: payload.value, name: nameFromUri(payload.value, kind, payload.mimeType ?? null), mime: payload.mimeType ?? null, size: 0 };
};

/** Something shared into Vitals from another app opens the Send sheet, already filled in. */
function useShareInbox() {
  const { sharedPayloads, resolvedSharedPayloads, isResolving, error, clearSharedPayloads } = useIncomingShare();
  const handled = useRef<string | null>(null);
  useEffect(() => {
    if (sharedPayloads.length === 0) {
      handled.current = null;
      return;
    }
    if (isResolving && error === null) return;
    const key = sharedPayloads.map((payload) => payload.value).join("\n");
    if (handled.current === key) return;
    const items = (error === null ? resolvedSharedPayloads.map(pickedOf) : sharedPayloads.map(rawPickedOf)).filter((item) => item !== null);
    if (items.length === 0 && error === null && resolvedSharedPayloads.length === 0) return;
    handled.current = key;
    if (items.length === 0) {
      clearSharedPayloads();
      return toast.show("Vitals can't send that to the Mac", { tone: "bad" });
    }
    openClipboard();
    sheet.open(sendSheet(batchOf(items, "shared from another app"), clearSharedPayloads));
  }, [sharedPayloads, resolvedSharedPayloads, isResolving, error, clearSharedPayloads]);
}

/** Clipboard work that runs whenever the app shell is up: auto-copy and the share inbox. */
export function ClipboardSync() {
  useAutoCopy();
  useShareInbox();
  return null;
}
