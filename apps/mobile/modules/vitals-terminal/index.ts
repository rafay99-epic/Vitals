import { requireNativeView } from "expo";
import type { ComponentType, Ref } from "react";
import { Platform, type NativeSyntheticEvent, type ViewProps } from "react-native";

export interface TerminalTheme {
  readonly background: string;
  readonly foreground: string;
  readonly cursor: string;
  readonly palette: ReadonlyArray<string>;
}

export interface TerminalSurfaceHandle {
  readonly feed: (data: string) => Promise<void>;
  readonly reset: () => Promise<void>;
  readonly scrollToBottom: () => Promise<void>;
  readonly focus: () => Promise<void>;
  readonly blur: () => Promise<void>;
}

export interface TerminalSurfaceProps extends ViewProps {
  readonly ref?: Ref<TerminalSurfaceHandle>;
  readonly fontSize: number;
  readonly theme: TerminalTheme;
  readonly onInput: (event: NativeSyntheticEvent<{ readonly data: string }>) => void;
  readonly onResize: (event: NativeSyntheticEvent<{ readonly cols: number; readonly rows: number }>) => void;
}

export const TerminalSurface: ComponentType<TerminalSurfaceProps> | null = Platform.OS === "android" ? requireNativeView<TerminalSurfaceProps>("VitalsTerminal") : null;
