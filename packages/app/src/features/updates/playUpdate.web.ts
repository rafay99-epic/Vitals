import { Store } from "@vitals/client-runtime";

export type PlayState = { readonly _tag: "Unavailable"; readonly reason: string };

export const playSupported = false;

export const playState = new Store<PlayState>({ _tag: "Unavailable", reason: "web app" });

export const playPrompt = new Store<string | null>(null);

export const checkPlay = async (): Promise<PlayState> => playState.get();

export const promptPlayOnLaunch = async (): Promise<void> => {};

export const dismissPlay = (): void => {};

export const startPlayUpdate = async (): Promise<boolean> => false;
