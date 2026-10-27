import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { clipTitle } from "@vitals/app/features/clips/format.ts";
import { dropLabel, isIncoming } from "@vitals/app/state/drops.ts";
import type { Clip } from "@vitals/contracts";
import { type ResolvedSharePayload, type SharePayload, useIncomingShare } from "expo-sharing";
import { useEffect, useRef } from "react";
import { AppState, Linking, Platform, ToastAndroid } from "react-native";

import { androidShare } from "../modules/vitals-share/index.ts";

import { autoCopy } from "./lib/autoCopy.ts";
import { batchOf, copyToPhone, isFile, nameFromUri, type Picked, textItem } from "./lib/clips.ts";
import { macFolder, savedTo } from "./lib/drops.ts";
import { checkPhoneCopy, phoneCopy, sendClipboardNow } from "./lib/phoneCopies.ts";
import { openClipboard, openFiles } from "./navigation.ts";
import { sendSheet } from "./sheets/ClipSheets.tsx";
import { askSheet } from "./sheets/FileSheets.tsx";
import { sheet, toast } from "./ui/index.ts";

const SHORT = 26;

const short = (text: string): string => (text.length > SHORT ? `${text.slice(0, SHORT)}…` : text);

const copyable = (clip: Clip): boolean => clip.kind === "text" || clip.kind === "link" || clip.kind === "image";

const copyNow = (remote: ReturnType<typeof useRemote>, clip: Clip) => () => void copyToPhone(remote, clip).then((copied) => copied && toast.show("Copied to this phone"));

/** While Vitals is open and the switch is on, each new Mac copy lands on this phone's clipboard. A clip the Mac sends on purpose always says so. */
function useAutoCopy() {
  const remote = useRemote();
  useEffect(
    () =>
      remote.clips.onAdded((clip) => {
        if (clip.deviceId !== null || AppState.currentState !== "active") return;
        const pushed = ("pushed" in clip && clip.pushed === true) || remote.clips.enabled.get() === false;
        if (pushed && !(autoCopy.get() && copyable(clip))) {
          toast.show("Your Mac sent its clipboard", copyable(clip) ? { action: "Copy", onAction: copyNow(remote, clip) } : { action: "Open", onAction: openClipboard });
          return;
        }
        if (!autoCopy.get() || !copyable(clip)) return;
        void copyToPhone(remote, clip).then((copied) => {
          if (!copied) return;
          if (pushed) toast.show("Your Mac sent its clipboard");
          else toast.show(clip.kind === "image" ? "Mac image is on this phone's clipboard" : `Mac copy is on this phone: ${short(clipTitle(clip))}`);
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
    if (items.some(isFile)) openFiles();
    else openClipboard();
    sheet.open(sendSheet(batchOf(items, "shared from another app"), clearSharedPayloads));
  }, [sharedPayloads, resolvedSharedPayloads, isResolving, error, clearSharedPayloads]);
}

const CHECK_AFTER_MS = 600;
const SEND_LINK = /:\/\/clipboard\/send\b/;
let launchLinkRead = false;

/** On return to Vitals, a new copy on this phone is offered to the Mac, or sent when the switch says so. */
function usePhoneCopies() {
  const remote = useRemote();
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | null = null;
    const check = () => {
      if (timer !== null) clearTimeout(timer);
      timer = setTimeout(() => void checkPhoneCopy(remote, Platform.OS !== "ios"), CHECK_AFTER_MS);
    };
    if (AppState.currentState === "active") check();
    const subscription = AppState.addEventListener("change", (state) => {
      if (state === "active") return check();
      phoneCopy.set(null);
    });
    return () => {
      if (timer !== null) clearTimeout(timer);
      subscription.remove();
    };
  }, [remote]);
}

/**
 * `<scheme>://clipboard/send`, from the Quick Settings tile or the Shortcuts action: send what is copied now.
 * When the link brought Vitals up from the background, it steps back to the app you were in.
 */
function useSendLink() {
  const remote = useRemote();
  useEffect(() => {
    let active = true;
    const handle = (url: string | null | undefined, away: boolean) => {
      if (!active || typeof url !== "string" || !SEND_LINK.test(url)) return;
      void sendClipboardNow(remote).then((sent) => {
        if (!sent || !away || androidShare === null) return;
        ToastAndroid.show("Sent to your Mac", ToastAndroid.SHORT);
        void androidShare.toBack();
      });
    };
    if (!launchLinkRead) {
      launchLinkRead = true;
      void Linking.getInitialURL().then((url) => handle(url, true));
    }
    const subscription = Linking.addEventListener("url", ({ url }) => handle(url, AppState.currentState !== "active"));
    return () => {
      active = false;
      subscription.remove();
    };
  }, [remote]);
}

const isPlural = (label: string): boolean => label.endsWith(" files");

/** Says where finished files landed, and asks before a Mac drop when Start without asking is off. */
function useDropNews() {
  const remote = useRemote();
  useEffect(
    () =>
      remote.drops.onFinish((finish) => {
        const label = dropLabel(finish.drop);
        const verb = isPlural(label) ? "are" : "is";
        if (finish._tag === "Received") toast.show(`${label} ${verb} in ${savedTo}`, { action: "Open", onAction: openFiles });
        else if (finish._tag === "Sent") toast.show(`${label} ${verb} in ${macFolder} on your Mac`);
        else toast.show(`Your Mac said no to ${label}`, { tone: "bad" });
      }),
    [remote],
  );
  useEffect(() => {
    const asked = new Set<string>();
    const me = remote.credentials.deviceId;
    return remote.drops.drops.subscribe(() => {
      if (remote.drops.autoAccept.get()) return;
      const fresh = remote.drops.drops.get().find((drop) => drop.state === "asking" && isIncoming(drop, me) && !asked.has(drop.id));
      if (fresh === undefined) return;
      asked.add(fresh.id);
      sheet.open(askSheet(fresh));
    });
  }, [remote]);
}

/** Clipboard and file work that runs whenever the app shell is up. */
export function ClipboardSync() {
  useAutoCopy();
  useShareInbox();
  usePhoneCopies();
  useSendLink();
  useDropNews();
  return null;
}
