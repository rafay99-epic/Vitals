import type { Clip } from "@vitals/contracts";
import { Button, Field, Mono, Row, Sans, Sheet } from "@vitals/ui";
import { useEffect, useState } from "react";
import { View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { haptics } from "../../lib/haptics";
import type { Moving } from "../../state/clips.ts";
import type { Remote } from "../../state/remote.ts";
import { fraction } from "../../state/transfer.ts";
import { useStore } from "../../state/useStore.ts";
import { useNow } from "../../state/useVitals.ts";
import { acceptDrops, chooseFiles, copyClipText, downloadClip, hasDom, sendOnPaste, sendToMac } from "../clips/browser.ts";
import { clipMeta, clipTitle } from "../clips/format.ts";

const ACCEPTED: ReadonlySet<string> = new Set(["done", "running"]);

const MAX_TEXT = 100_000;

/** The web list stays short; the phone has the full history. */
const SHOWN = 30;

function MovingLine({ moving }: { readonly moving: Moving }) {
  const progress = useStore(moving.transfer.progress);
  const tail = progress.phase === "waiting" ? "waiting for the Mac" : `${String(Math.round(fraction(progress) * 100))}%`;
  return (
    <View className="flex-row items-center justify-between gap-3 px-[22px] py-2">
      <Mono tone="ink" numberOfLines={1} className="shrink">{`${moving.transfer.label} · ${tail}`}</Mono>
      <Button label="Cancel" variant="text" small onPress={() => moving.transfer.cancel()} />
    </View>
  );
}

function ClipLine({ clip, remote, now }: { readonly clip: Clip; readonly remote: Remote; readonly now: number }) {
  const text = clip.kind === "text" || clip.kind === "link";
  const act = () =>
    void (text ? copyClipText(remote, clip) : downloadClip(remote, clip)).then((ok) => {
      if (ok && text) remote.show("Copied.");
    });
  const title = clipTitle(clip);
  return <Row label={title.length > 80 ? `${title.slice(0, 79)}…` : title} detail={clipMeta(clip, remote.credentials.deviceId, now, "this browser")} trailing={<Button label={text ? "Copy" : "Download"} variant="line" small onPress={act} />} />;
}

/** History from the Mac with Copy and Download, plus a drop zone, file picker and paste to send. */
function History({ canRead, canWrite }: { readonly canRead: boolean; readonly canWrite: boolean }) {
  const remote = useRemote();
  const clips = useStore(remote.clips.clips);
  const enabled = useStore(remote.clips.enabled);
  const moving = useStore(remote.clips.moving);
  const now = useNow(30_000);
  const [text, setText] = useState("");
  // On the web a View is a DOM element; it is kept in state so the drop listener attaches once it mounts.
  const [zone, setZone] = useState<unknown>(null);

  useEffect(() => (canWrite ? acceptDrops(zone, (files) => void sendToMac(remote, files, null)) : undefined), [remote, canWrite, zone]);
  useEffect(() => (canWrite ? sendOnPaste((files, pasted) => void sendToMac(remote, files, pasted)) : undefined), [remote, canWrite]);

  const sendText = () => {
    haptics.success();
    void sendToMac(remote, [], text).then((ok) => ok && setText(""));
  };

  return (
    <>
      <Field label="Text for the Mac clipboard" value={text} onChangeText={setText} multiline maxLength={MAX_TEXT} editable={canWrite} placeholder="Paste or type" />
      <View className="gap-2.5 px-[22px] pb-3">
        <Button label="Send to Mac" block disabled={!canWrite || text.trim().length === 0} onPress={sendText} />
      </View>
      {canWrite && hasDom ? (
        <View ref={setZone} className="mx-[22px] mb-3 items-center gap-2 border border-dashed border-line3 px-4 py-5">
          <Sans size="small" tone="dim">
            Drop files here, or paste, to send to the Mac
          </Sans>
          <Button label="Choose files" variant="line" small onPress={() => chooseFiles((files) => void sendToMac(remote, files, null))} />
        </View>
      ) : null}
      {moving.map((item) => (
        <MovingLine key={item.id} moving={item} />
      ))}
      {!canRead ? (
        <Mono className="px-[22px] pb-4">Reading the Mac clipboard is off for this device.</Mono>
      ) : enabled === false ? (
        <Mono className="px-[22px] pb-4">Clipboard history is off on the Mac. Turn it on in Vitals on the Mac, under Remote.</Mono>
      ) : enabled === null ? (
        <Mono className="px-[22px] pb-4">Reading the Mac.</Mono>
      ) : clips.length === 0 ? (
        <Mono className="px-[22px] pb-4">Nothing copied yet</Mono>
      ) : (
        clips.slice(0, SHOWN).map((clip) => <ClipLine key={clip.id} clip={clip} remote={remote} now={now} />)
      )}
    </>
  );
}

/** Macs from before clip history: plain text to the Mac, and read what it copied. */
function PlainText({ canRead, canWrite, onSent }: { readonly canRead: boolean; readonly canWrite: boolean; readonly onSent: () => void }) {
  const remote = useRemote();
  const [text, setText] = useState("");
  const [macText, setMacText] = useState<string | null>(null);
  const [sending, setSending] = useState(false);

  const copy = () => {
    haptics.success();
    setSending(true);
    void remote.run({ _tag: "ClipboardSet", text }).then((receipt) => {
      setSending(false);
      if (!ACCEPTED.has(receipt?.status ?? "failed")) return;
      remote.show("Copied to the Mac clipboard.");
      setText("");
      onSent();
    });
  };

  const read = () =>
    void remote.connection.call((client) => client["clipboard.get"]({})).then((result) => {
      if (result.ok) setMacText(result.value.text ?? "The Mac clipboard is empty.");
      else remote.show(result.error.message, "bad");
    });

  return (
    <>
      <Field label="Text for the Mac clipboard" value={text} onChangeText={setText} multiline maxLength={MAX_TEXT} editable={canWrite} placeholder="Paste or type" hint={`${String(text.length)} characters`} />
      <View className="gap-2.5 px-[22px] pb-4">
        <Button label="Copy to Mac" block disabled={!canWrite || sending || text.length === 0} onPress={copy} accessibilityHint={canWrite ? undefined : "Control is off for this device on the Mac."} />
        <Button label="Read Mac clipboard" variant="line" block disabled={!canRead} onPress={read} accessibilityHint={canRead ? undefined : "Clipboard reading is off for this device on the Mac."} />
        {macText === null ? null : (
          <Mono tone="ink" selectable className="mt-1 leading-5">
            {macText}
          </Mono>
        )}
      </View>
    </>
  );
}

export function ClipboardSheet({ visible, canRead, canWrite, onClose }: { readonly visible: boolean; readonly canRead: boolean; readonly canWrite: boolean; readonly onClose: () => void }) {
  const remote = useRemote();
  const supported = useStore(remote.clips.supported);
  const count = useStore(remote.clips.clips).length;
  const modern = supported !== false;
  const detail = modern ? (canRead ? `${String(count)} on the Mac` : "send text and files") : "plain text · up to 100 KB";
  return (
    <Sheet visible={visible} title="Clipboard" detail={detail} onClose={onClose}>
      {visible ? modern ? <History canRead={canRead} canWrite={canWrite} /> : <PlainText canRead={canRead} canWrite={canWrite} onSent={onClose} /> : null}
    </Sheet>
  );
}
