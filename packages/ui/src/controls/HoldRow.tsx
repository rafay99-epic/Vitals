import { useEffect, useState } from "react";
import { type LayoutChangeEvent, Pressable } from "react-native";
import { cancelAnimation, Easing, runOnJS, useSharedValue, withTiming } from "react-native-reanimated";

import { channels, motion } from "../theme.ts";
import { Mono, Serif } from "../typography.tsx";
import { HoldTrace } from "./HoldTrace";

export type HoldKind = "hold" | "consent";

export interface HoldRowProps {
  readonly label: string;
  readonly hint?: string | undefined;
  readonly kind?: HoldKind | undefined;
  readonly danger?: boolean | undefined;
  readonly locked?: boolean | undefined;
  readonly compact?: boolean | undefined;
  readonly onStart?: (() => void) | undefined;
  readonly onCommit: () => void;
  readonly accessibilityHint?: string | undefined;
}

const DURATION: Record<HoldKind, number> = { hold: motion.hold, consent: motion.consent };
const SENT_MS = 1800;

const sentTone = (sent: boolean) => (sent ? "pulse" : "ink");

export function HoldRow({ label, hint, kind = "hold", danger = false, locked = false, compact = false, onStart, onCommit, accessibilityHint }: HoldRowProps) {
  const [size, setSize] = useState({ width: 0, height: 0 });
  const [sent, setSent] = useState(false);
  const progress = useSharedValue(0);
  const duration = DURATION[kind];
  const color = danger ? channels.press.color : channels.pulse.color;

  useEffect(() => {
    if (!sent) return;
    const timer = setTimeout(() => {
      setSent(false);
      progress.set(withTiming(0, { duration: motion.release }));
    }, SENT_MS);
    return () => clearTimeout(timer);
  }, [sent, progress]);

  const commit = () => {
    setSent(true);
    onCommit();
  };

  const busy = locked || sent;

  const begin = () => {
    if (busy) return;
    onStart?.();
    progress.set(
      withTiming(1, { duration, easing: Easing.linear }, (finished) => {
        if (finished === true) runOnJS(commit)();
      }),
    );
  };

  const release = () => {
    if (progress.get() >= 1) return;
    cancelAnimation(progress);
    progress.set(withTiming(0, { duration: motion.release }));
  };

  const seconds = Math.round(duration / 100) / 10;

  return (
    <Pressable
      onPressIn={begin}
      onPressOut={release}
      disabled={busy}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityHint={accessibilityHint ?? `Double tap and hold for ${seconds} seconds.`}
      accessibilityState={{ disabled: busy }}
      accessibilityActions={[{ name: "activate", label }]}
      onAccessibilityAction={(event) => {
        if (event.nativeEvent.actionName === "activate" && !busy) commit();
      }}
      onLayout={(event: LayoutChangeEvent) => setSize({ width: event.nativeEvent.layout.width, height: event.nativeEvent.layout.height })}
      className={`flex-row items-center justify-between border-y border-line2 px-[22px] ${compact ? "min-h-16" : "min-h-[92px]"} ${locked ? "opacity-40" : ""}`}
    >
      {size.width === 0 ? null : (
        <HoldTrace width={size.width} height={size.height} color={color} progress={progress} />
      )}
      <Serif size={compact ? "m" : "l"} tone={danger ? "press" : sentTone(sent)} numberOfLines={1}>
        {label}
      </Serif>
      {hint === undefined ? null : (
        <Mono className="max-w-[48%] text-right text-[10px] leading-4">{sent ? `${hint} · sent` : hint}</Mono>
      )}
    </Pressable>
  );
}
