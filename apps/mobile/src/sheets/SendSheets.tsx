import { sessions } from "@vitals/app/connection/session.ts";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { useState } from "react";

import { send } from "../lib/remote.ts";
import { BigButton, Field, Hold, sheet, SheetCancel, SheetHeader, SheetNote } from "../ui/index.ts";

const LINK = /^https?:\/\/\S+$/;

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
