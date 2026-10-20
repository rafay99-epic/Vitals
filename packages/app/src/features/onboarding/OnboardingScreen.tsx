import { Button, channels, colors, Mark, Mono, Sans, Serif, Tag } from "@vitals/ui";
import * as Clipboard from "expo-clipboard";
import { type ReactNode, useState } from "react";
import { Linking, Pressable, ScrollView, Share, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { FirstBeat } from "../../components/FirstBeat.tsx";
import { haptics } from "../../lib/haptics";
import { BREW_INSTALL, SITE_URL, TAILSCALE_STORE_URL } from "../../lib/links.ts";
import { finishOnboarding } from "../../persistence/onboarding";

type Page = "welcome" | "mac" | "remote" | "tailscale" | "pair";

const ORDER: ReadonlyArray<Page> = ["welcome", "mac", "remote", "tailscale", "pair"];

interface PageSpec {
  readonly kicker: string;
  readonly title: string;
  readonly body: string;
  readonly next: string;
  readonly aside?: { readonly label: string; readonly run: () => void } | undefined;
  readonly art: () => ReactNode;
}

function Line() {
  return (
    <View className="my-6 justify-center border-y border-line py-10">
      <FirstBeat />
    </View>
  );
}

function CopyRow({ text, action, onPress }: { readonly text: string; readonly action: string; readonly onPress: () => void }) {
  return (
    <Pressable onPress={onPress} accessibilityRole="button" accessibilityLabel={`${action} ${text}`} className="min-h-12 flex-row items-center justify-between gap-3 border border-line3 px-3 active:bg-raise">
      <Mono tone="ink" className="flex-1" numberOfLines={2}>
        {text}
      </Mono>
      <Mono>{action}</Mono>
    </Pressable>
  );
}

function GetTheMac() {
  const [copy, setCopy] = useState<"copy" | "copied" | "copy failed">("copy");
  const copyInstall = () => {
    void Clipboard.setStringAsync(BREW_INSTALL)
      .catch(() => false)
      .then((done) => {
        (done ? haptics.success : haptics.error)();
        setCopy(done ? "copied" : "copy failed");
      });
  };
  const share = () => {
    void Share.share({ message: `Vitals for Mac: ${SITE_URL}` }).catch(() => undefined);
  };
  return (
    <View className="gap-3 px-[22px] pt-6">
      <CopyRow text={BREW_INSTALL} action={copy} onPress={copyInstall} />
      <CopyRow text={SITE_URL.replace("https://", "")} action="share" onPress={share} />
      <Mono>Send the link to your Mac with AirDrop or a message, then open it there.</Mono>
    </View>
  );
}

function SketchRow({ label, on }: { readonly label: string; readonly on: boolean }) {
  return <Mono tone={on ? "ink" : "dim"} className="text-[10px]">{label}</Mono>;
}

function MacSketch() {
  return (
    <View className="mx-[22px] mt-6 border border-line3" accessible accessibilityLabel="Vitals on the Mac: sidebar, Remote, remote access switched on">
      <View className="h-6 flex-row items-center justify-between border-b border-line2 px-2.5">
        <Mono className="text-[10px]">Vitals</Mono>
        <Mono className="text-[10px]">9:41</Mono>
      </View>
      <View className="h-40 flex-row">
        <View className="w-28 gap-2 border-r border-line2 p-2.5">
          <SketchRow label="Overview" on={false} />
          <SketchRow label="CPU" on={false} />
          <SketchRow label="Memory" on={false} />
          <SketchRow label="Cleanup" on={false} />
          <SketchRow label="Remote" on />
        </View>
        <View className="flex-1 gap-2.5 p-2.5">
          <View className="flex-row items-center justify-between">
            <Mono tone="ink" className="text-[10px]">Remote access</Mono>
            <View className="h-3.5 w-6 items-end justify-center rounded-full bg-pulse px-0.5">
              <View className="h-2.5 w-2.5 rounded-full bg-bg" />
            </View>
          </View>
          <Mono className="text-[10px]">Serving on your tailnet</Mono>
          <Mono tone="ink" className="text-[10px]">Pair new device</Mono>
        </View>
      </View>
    </View>
  );
}

function Device({ name }: { readonly name: string }) {
  return (
    <View className="flex-1 items-center gap-1 border border-line3 py-3">
      <Serif size="s">{name}</Serif>
      <Mono className="text-[10px]">signed in</Mono>
    </View>
  );
}

function Tailnet() {
  return (
    <View className="gap-3 px-[22px] pt-6">
      <View className="h-32 flex-row items-center gap-3" accessible accessibilityLabel="Phone and Mac, both signed in to Tailscale">
        <Device name="Phone" />
        <Mark width={56} />
        <Device name="Mac" />
      </View>
      <CopyRow text="Tailscale for this phone" action="open" onPress={() => void Linking.openURL(TAILSCALE_STORE_URL)} />
      <CopyRow text="tailscale.com/download for the Mac" action="share" onPress={() => void Share.share({ message: "Tailscale for Mac: https://tailscale.com/download/mac" }).catch(() => undefined)} />
    </View>
  );
}

const PAGES: Record<Page, PageSpec> = {
  welcome: {
    kicker: "Welcome",
    title: "The bedside chart for your Mac.",
    body: "Watch, quiet and put your Mac to sleep from here. It needs one thing first: Vitals running on the Mac.",
    next: "Start",
    aside: { label: "I already have it", run: finishOnboarding },
    art: Line,
  },
  mac: {
    kicker: "Step 1 of 4",
    title: "Get Vitals for Mac.",
    body: "Free and open source, for Apple silicon Macs on macOS 15 or later. Install it with Homebrew or download it from the site.",
    next: "It is installed",
    art: GetTheMac,
  },
  remote: {
    kicker: "Step 2 of 4",
    title: "Turn on Remote.",
    body: "Open Vitals on the Mac. In the sidebar under Maintain, pick Remote and switch on remote access.",
    next: "Remote is on",
    art: MacSketch,
  },
  tailscale: {
    kicker: "Step 3 of 4",
    title: "Tailscale on both.",
    body: "Vitals talks to your Mac only over your own tailnet. Sign in to Tailscale with the same account on the Mac and on this phone.",
    next: "Both are on",
    art: Tailnet,
  },
  pair: {
    kicker: "Step 4 of 4",
    title: "Pair this phone.",
    body: "In Remote on the Mac, choose Pair new device. A code appears. Scan it next.",
    next: "Scan the code",
    art: Line,
  },
};

function Progress({ index }: { readonly index: number }) {
  return (
    <View className="flex-row gap-1.5 px-[22px] pt-2" accessible accessibilityLabel={`Page ${String(index + 1)} of ${String(ORDER.length)}`}>
      {ORDER.map((page, position) => (
        <View key={page} className="h-0.5 flex-1" style={{ backgroundColor: position <= index ? channels.pulse.color : colors.line3 }} />
      ))}
    </View>
  );
}

export function OnboardingScreen() {
  const insets = useSafeAreaInsets();
  const [index, setIndex] = useState(0);
  const page = ORDER[index] ?? "welcome";
  const spec = PAGES[page];
  const Art = spec.art;
  const last = index === ORDER.length - 1;
  const next = () => {
    haptics.select();
    if (last) {
      finishOnboarding();
      return;
    }
    setIndex(index + 1);
  };
  const back = () => setIndex(Math.max(0, index - 1));
  const aside = spec.aside ?? (index > 0 ? { label: "Back", run: back } : undefined);
  return (
    <View className="flex-1 bg-bg" style={{ paddingTop: insets.top, paddingBottom: Math.max(insets.bottom, 16) }}>
      <Progress index={index} />
      <ScrollView className="flex-1" contentContainerClassName="pb-6">
        <View className="gap-3 px-[22px] pt-6">
          <Tag tone="dim">{spec.kicker}</Tag>
          <Serif size="l" accessibilityRole="header">
            {spec.title}
          </Serif>
          <Sans tone="ink2">{spec.body}</Sans>
        </View>
        <Art />
      </ScrollView>
      <View className="flex-row items-center justify-between px-[22px] pt-3">
        {aside === undefined ? <View /> : <Button label={aside.label} variant="text" onPress={aside.run} />}
        <Button label={spec.next} onPress={next} />
      </View>
    </View>
  );
}
