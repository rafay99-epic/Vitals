import { Easing, FadeIn, FadeInDown, FadeOut } from "react-native-reanimated";

import { motion } from "./theme.ts";

const ease = Easing.bezier(0.2, 0.8, 0.2, 1);

const STAGGER_MS = 45;

export const rise = (order = 0) =>
  FadeInDown.duration(motion.sample)
    .delay(order * STAGGER_MS)
    .easing(ease)
    .withInitialValues({ opacity: 0, transform: [{ translateY: 8 }] });

export const swap = FadeIn.duration(motion.sample).easing(ease);

export const leave = FadeOut.duration(motion.toastIn);

export const settle = undefined;
