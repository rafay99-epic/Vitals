import { Button, Field, Mono, Sheet } from "@vitals/ui";
import { useRef, useState } from "react";
import { View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { haptics } from "../../lib/haptics";

const ACCEPTED: ReadonlySet<string> = new Set(["done", "running"]);

const MAX_TEXT = 100_000;

export function ClipboardSheet({ visible, canRead, canWrite, onClose }: { readonly visible: boolean; readonly canRead: boolean; readonly canWrite: boolean; readonly onClose: () => void }) {
  const remote = useRemote();
  const [text, setText] = useState("");
  const [macText, setMacText] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const request = useRef(0);

  const close = () => {
    request.current += 1;
    setMacText(null);
    onClose();
  };

  const copy = () => {
    haptics.success();
    setSending(true);
    const id = request.current;
    void remote.run({ _tag: "ClipboardSet", text }).then((receipt) => {
      setSending(false);
      if (!ACCEPTED.has(receipt?.status ?? "failed")) return;
      remote.show("Copied to the Mac clipboard.");
      if (id !== request.current) return;
      setText("");
      close();
    });
  };

  const read = () =>
    void remote.connection.call((client) => client["clipboard.get"]({})).then((result) => {
      if (result.ok) setMacText(result.value.text ?? "The Mac clipboard is empty.");
      else remote.show(result.error.message, "bad");
    });

  return (
    <Sheet visible={visible} title="Clipboard" detail="plain text · up to 100 KB" onClose={close}>
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
    </Sheet>
  );
}
