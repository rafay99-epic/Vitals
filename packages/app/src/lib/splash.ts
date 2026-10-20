import * as SplashScreen from "expo-splash-screen";

void SplashScreen.preventAutoHideAsync().catch(() => undefined);

export const hideSplash = (): void => {
  void SplashScreen.hideAsync().catch(() => undefined);
};
