import * as Haptics from "expo-haptics";

export const haptics = {
  select: () => void Haptics.selectionAsync(),
  soft: () => void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Soft),
  light: () => void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light),
  heavy: () => void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy),
  success: () => void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success),
  warning: () => void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning),
  error: () => void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error),
} as const;
