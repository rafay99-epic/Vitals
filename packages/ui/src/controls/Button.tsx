import { Pressable } from "react-native";

import { Sans, type Tone } from "../typography.tsx";

export type ButtonVariant = "primary" | "line" | "text" | "danger";

const VARIANT: Record<ButtonVariant, { readonly box: string; readonly tone: Tone }> = {
  primary: { box: "bg-ink active:bg-ink2", tone: "black" },
  line: { box: "border border-line3 active:bg-raise", tone: "ink" },
  text: { box: "px-1", tone: "ink" },
  danger: { box: "bg-press active:opacity-80", tone: "black" },
};

export interface ButtonProps {
  readonly label: string;
  readonly onPress: () => void;
  readonly variant?: ButtonVariant | undefined;
  readonly small?: boolean | undefined;
  readonly block?: boolean | undefined;
  readonly disabled?: boolean | undefined;
  readonly accessibilityHint?: string | undefined;
}

export function Button({ label, onPress, variant = "primary", small = false, block = false, disabled = false, accessibilityHint }: ButtonProps) {
  const style = VARIANT[variant];
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityHint={accessibilityHint}
      accessibilityState={{ disabled }}
      className={`items-center justify-center ${small ? "min-h-9 px-3.5" : "min-h-12 px-5"} ${block ? "self-stretch" : "self-start"} ${style.box} ${disabled ? "opacity-35" : ""}`}
    >
      <Sans size={small ? "small" : "body"} weight="medium" tone={style.tone} className={variant === "text" ? "underline" : ""}>
        {label}
      </Sans>
    </Pressable>
  );
}
