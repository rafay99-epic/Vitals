import * as Haptics from "expo-haptics";

export const tick = (): void => {
  void Haptics.selectionAsync();
};

export const thud = (): void => {
  void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
};

export const success = (): void => {
  void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
};
