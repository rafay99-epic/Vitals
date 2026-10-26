import { requireNativeModule } from "expo";
import { AppRegistry, Platform } from "react-native";

const TASK = "VitalsShare";

interface Native {
  readonly start: () => Promise<boolean>;
  readonly stop: () => Promise<void>;
}

const native = Platform.OS === "android" ? requireNativeModule<Native>("VitalsShare") : null;
let wanted = false;
let release: (() => void) | null = null;

if (native !== null) {
  AppRegistry.registerHeadlessTask(TASK, () => () =>
    new Promise<void>((resolve) => {
      if (wanted) release = resolve;
      else resolve();
    }),
  );
}

export const sharesInBackground = native !== null;

const finish = (): void => {
  release?.();
  release = null;
  void native?.stop();
};

export const holdSharing = async (): Promise<boolean> => {
  if (native === null) return false;
  if (wanted) return true;
  wanted = true;
  const started = await native.start();
  if (!started) wanted = false;
  else if (!wanted) finish();
  return started && wanted;
};

export const releaseSharing = (): void => {
  if (!wanted) return;
  wanted = false;
  finish();
};
