import { sessions } from "@vitals/app/connection/session.ts";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { useState } from "react";
import { StyleSheet } from "react-native";

import { send, useAccess } from "../lib/remote.ts";
import { BigButton, color, Field, Hold, sheet, SheetCancel, SheetHeader, SheetNote, T, toast } from "../ui/index.ts";

const MAX_TEXT = 100_000;
const LINK = /^https?:\/\/\S+$/;

/** Send text to the Mac clipboard, or read what the Mac copied. */
export function ClipboardSheet() {
  const remote = useRemote();
  const access = useAccess();
  const [text, setText] = useState("");
  const [macText, setMacText] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const copy = () => {
    setBusy(true);
    void send(remote, { _tag: "ClipboardSet", text }, "Copied to your Mac").then((ok) => {
      setBusy(false);
      if (ok) sheet.close();
    });
  };
  const read = () =>
    void remote.connection.call((client) => client["clipboard.get"]({})).then((result) => {
      if (result.ok) setMacText(result.value.text ?? "The Mac clipboard is empty.");
      else toast.show(result.error.message, { tone: "bad" });
    });

  return (
    <>
      <SheetHeader title="Clipboard" detail="Plain text, up to 100 KB." />
      <Field tall value={text} onChangeText={setText} maxLength={MAX_TEXT} editable={access.operate} placeholder="Type or paste here" accessibilityLabel="Text for the Mac" />
      <BigButton label="Send to Mac" disabled={!access.operate || busy || text.length === 0} onPress={copy} />
      <BigButton ghost label="Get the Mac's clipboard" disabled={!access.clipboard} onPress={read} />
      {access.clipboard ? null : <SheetNote>Reading the Mac clipboard is off for this phone.</SheetNote>}
      {macText === null ? null : (
        <T v="mono" color={color.ink} selectable style={styles.mac}>
          {macText}
        </T>
      )}
    </>
  );
}

/** Open a link in the Mac's default browser. */
export function LinkSheet() {
  const remote = useRemote();
  const [url, setUrl] = useState("");
  const [busy, setBusy] = useState(false);
  const valid = LINK.test(url.trim());
  const open = () => {
    setBusy(true);
    void send(remote, { _tag: "OpenUrl", url: url.trim() }, "Opened on your Mac").then((ok) => {
      setBusy(false);
      if (ok) sheet.close();
    });
  };
  return (
    <>
      <SheetHeader title="Open a link" detail="Opens in your Mac's default browser." />
      <Field value={url} onChangeText={setUrl} placeholder="https://" autoCapitalize="none" autoCorrect={false} keyboardType="url" autoFocus accessibilityLabel="Link" />
      {url.length > 0 && !valid ? <SheetNote>Use a full link that starts with http or https.</SheetNote> : null}
      <BigButton label="Open on Mac" disabled={!valid || busy} onPress={open} />
    </>
  );
}

/** Forget this Mac. Needs a new code from the Mac to pair again. */
export function UnpairSheet() {
  return (
    <>
      <SheetHeader title="Unpair this phone?" detail="You will need a new code from the Mac to connect again." />
      <Hold
        label="Hold to unpair"
        onCommit={() => {
          sheet.close();
          void sessions.forget();
        }}
      />
      <SheetCancel />
    </>
  );
}

const styles = StyleSheet.create({
  mac: { paddingHorizontal: 20, paddingTop: 12, lineHeight: 20 },
});
