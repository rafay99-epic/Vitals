import { Button, Field, Mono, Sheet } from "@vitals/ui";
import { useState } from "react";
import { View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { haptics } from "../../lib/haptics";

export function ClipboardSheet({ visible, canRead, onClose }: { readonly visible: boolean; readonly canRead: boolean; readonly onClose: () => void }) {
  const remote = useRemote();
  const [text, setText] = useState("");
  const [macText, setMacText] = useState<string | null>(null);

  const copy = () => {
    haptics.success();
    void remote.run({ _tag: "ClipboardSet", text }).then((receipt) => {
      if (receipt === null) return;
      remote.show("Copied to the Mac clipboard.");
      setText("");
      onClose();
    });
  };

  const read = () =>
    void remote.connection.call((client) => client["clipboard.get"]({})).then((result) => {
      if (result.ok) setMacText(result.value.text ?? "The Mac clipboard is empty.");
      else remote.show(result.error.message, "bad");
    });

  return (
    <Sheet visible={visible} title="Clipboard" detail="plain text · up to 100 KB" onClose={onClose}>
      <Field label="Text for the Mac clipboard" value={text} onChangeText={setText} multiline placeholder="Paste or type" hint={`${String(text.length)} characters`} />
      <View className="gap-2.5 px-[22px] pb-4">
        <Button label="Copy to Mac" block disabled={text.length === 0} onPress={copy} />
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
