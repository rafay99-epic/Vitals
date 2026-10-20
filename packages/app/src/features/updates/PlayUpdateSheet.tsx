import { Button, Sans, Sheet } from "@vitals/ui";
import { useEffect } from "react";
import { View } from "react-native";

import { useStore } from "../../state/useStore.ts";
import { dismissPlay, playPrompt, promptPlayOnLaunch, startPlayUpdate } from "./playUpdate";

export function PlayUpdateSheet() {
  const version = useStore(playPrompt);
  useEffect(() => {
    void promptPlayOnLaunch();
  }, []);
  return (
    <Sheet visible={version !== null} title="A new Vitals is out." detail={`on Google Play · version ${version ?? ""}`} onClose={dismissPlay}>
      <View className="gap-4 px-[22px] pb-5">
        <Sans tone="ink2">This one comes from the store because it changes native parts. It downloads in the background while you keep using Vitals, then the app restarts into it.</Sans>
        <Button label="Update now" block onPress={() => void startPlayUpdate()} />
      </View>
    </Sheet>
  );
}
