import { ScreenHeader, type Tone } from "@vitals/ui";
import type { ReactNode } from "react";

import { useRemote } from "../connection/useRemote.ts";
import { useLink, useWord } from "../state/useVitals.ts";
import { useStore } from "../state/useStore.ts";

export interface TabHeaderProps {
  readonly title?: string | undefined;
  readonly titleTone?: Tone | undefined;
  readonly meta?: ReactNode;
  readonly metaTone?: Tone | undefined;
}

function WordTitle({ meta, metaTone }: Pick<TabHeaderProps, "meta" | "metaTone">) {
  const word = useWord();
  return <Header word={word.word} tone={word.tone} meta={meta} metaTone={metaTone} />;
}

function Header({ word, tone, meta, metaTone }: { readonly word: string; readonly tone: Tone } & Pick<TabHeaderProps, "meta" | "metaTone">) {
  const remote = useRemote();
  const state = useStore(remote.connection.state);
  const link = useLink();
  const who = state._tag === "Ready" && state.hello.mac !== null ? state.hello.mac.name : "Your Mac";
  return <ScreenHeader who={who} link={link.label} linkTone={link.tone} word={word} wordTone={tone} meta={meta} metaTone={metaTone} />;
}

export function TabHeader({ title, titleTone = "ink", meta, metaTone }: TabHeaderProps) {
  return title === undefined ? <WordTitle meta={meta} metaTone={metaTone} /> : <Header word={title} tone={titleTone} meta={meta} metaTone={metaTone} />;
}
