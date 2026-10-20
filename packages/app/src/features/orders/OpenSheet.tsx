import { Button, Field, Sheet } from "@vitals/ui";
import { useState } from "react";
import { View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { haptics } from "../../lib/haptics";

const LINK = /^https?:\/\/\S+$/;

export function OpenSheet({ visible, onClose }: { readonly visible: boolean; readonly onClose: () => void }) {
  const remote = useRemote();
  const [url, setUrl] = useState("");
  const valid = LINK.test(url);

  const open = () => {
    haptics.success();
    void remote.run({ _tag: "OpenUrl", url }).then((receipt) => {
      if (receipt === null) return;
      setUrl("");
      onClose();
    });
  };

  return (
    <Sheet visible={visible} title="Open on Mac" detail="opens in the Mac's default browser" onClose={onClose}>
      <Field
        label="Link"
        mono
        value={url}
        onChangeText={setUrl}
        placeholder="https://"
        autoCapitalize="none"
        autoCorrect={false}
        keyboardType="url"
        error={url.length > 0 && !valid ? "Use a full http or https link." : null}
      />
      <View className="px-[22px] pb-4">
        <Button label="Open on Mac" block disabled={!valid} onPress={open} />
      </View>
    </Sheet>
  );
}
