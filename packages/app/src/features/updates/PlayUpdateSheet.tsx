import { Button, Sans, Sheet } from "@vitals/ui";
import { useEffect, useState } from "react";
import { View } from "react-native";

import { useStore } from "../../state/useStore.ts";
import { dismissPlay, playPrompt, promptPlayOnLaunch, startPlayUpdate } from "./playUpdate";

export function PlayUpdateSheet() {
  const version = useStore(playPrompt);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    void promptPlayOnLaunch();
  }, []);
  const close = () => {
    setFailed(false);
    dismissPlay();
  };
  return (
    <Sheet visible={version !== null} title="A new Vitals is out." detail={`on Google Play · version ${version ?? ""}`} onClose={close}>
      <View className="gap-4 px-[22px] pb-5">
        <Sans tone="ink2">This one comes from the store because it changes native parts. It downloads in the background while you keep using Vitals, then the app restarts into it.</Sans>
        {failed ? (
          <Sans tone="alarmHigh" accessibilityLiveRegion="assertive">
            Google Play did not open. Try again.
          </Sans>
        ) : null}
        <Button label="Update now" block onPress={() => void startPlayUpdate().then((started) => setFailed(!started))} />
      </View>
    </Sheet>
  );
}
