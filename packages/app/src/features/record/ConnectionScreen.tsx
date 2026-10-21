import type { NativeStackScreenProps } from "@react-navigation/native-stack";
import { BackHeader, Button, Mono, Row, Screen, Section, Serif, type Tone } from "@vitals/ui";
import { useState } from "react";
import { Linking, View } from "react-native";

import { nearby, nearbyEndpoints } from "../../connection/nearby.ts";
import { startTunnel, tailnetSupported, type Tunnel, tunnel } from "../../connection/tunnel.ts";
import { useRemote } from "../../connection/useRemote.ts";
import { hostOf } from "../../lib/host.ts";
import { TAILSCALE_STORE_URL } from "../../lib/links.ts";
import type { RecordStackParams } from "../../navigation/types.ts";
import { useStore } from "../../state/useStore.ts";

type Props = NativeStackScreenProps<RecordStackParams, "Connection">;

type Test = { readonly _tag: "Idle" } | { readonly _tag: "Testing" } | { readonly _tag: "Works"; readonly ms: number } | { readonly _tag: "Down" };

const testTailnet = async (baseUrl: string): Promise<Test> => {
  const startedAt = Date.now();
  const ok = await fetch(`${baseUrl}/api/health`, { signal: AbortSignal.timeout(5_000) })
    .then((response) => response.ok)
    .catch(() => false);
  return ok ? { _tag: "Works", ms: Date.now() - startedAt } : { _tag: "Down" };
};

const TEST_LINE: Record<Test["_tag"], string> = {
  Idle: "Test",
  Testing: "Testing",
  Works: "works",
  Down: "did not answer",
};

type RouteKind = "lan" | "tailnet" | null;

const wifiValue = (route: RouteKind, known: boolean): { readonly value: string; readonly tone: Tone } => {
  if (route === "lan") return { value: "in use", tone: "pulse" };
  return { value: known ? "ready" : "away", tone: "dim" };
};

const tailnetValue = (route: RouteKind, configured: boolean): { readonly value: string; readonly tone: Tone } => {
  if (route === "tailnet") return { value: "in use", tone: "resp" };
  return configured ? { value: "ready", tone: "dim" } : { value: "set up", tone: "alarmMedium" };
};

const TUNNEL_VALUE: Record<Tunnel["_tag"], string> = {
  Off: "Turn on",
  Starting: "starting",
  NeedsLogin: "Sign in",
  Ready: "on",
  Failed: "Try again",
};

function BuiltInTailscale() {
  const remote = useRemote();
  const state = useStore(tunnel);
  const link = useStore(remote.link);
  const press = () => {
    if (state._tag === "NeedsLogin") return void Linking.openURL(state.url);
    if (state._tag === "Ready" || state._tag === "Starting") return;
    remote.setBuiltInTailscale(true);
    void startTunnel({ ...link, builtInTailscale: true });
  };
  const detail = state._tag === "Failed" ? state.reason : "No Tailscale app needed on this phone";
  return (
    <Row
      plain
      label="Built-in Tailscale"
      detail={detail}
      value={TUNNEL_VALUE[state._tag]}
      valueTone={state._tag === "Ready" ? "resp" : "ink"}
      onPress={state._tag === "Ready" || state._tag === "Starting" ? undefined : press}
    />
  );
}

function Step({ done, label, detail, action, onPress }: { readonly done: boolean; readonly label: string; readonly detail?: string; readonly action?: string; readonly onPress?: () => void }) {
  return <Row plain label={`${done ? "✓" : "·"} ${label}`} detail={detail} value={done ? undefined : action} valueTone="ink" onPress={done ? undefined : onPress} />;
}

export function ConnectionScreen({ navigation }: Props) {
  const remote = useRemote();
  const link = useStore(remote.link);
  const state = useStore(remote.connection.state);
  useStore(nearby);
  const [test, setTest] = useState<Test>({ _tag: "Idle" });
  const tailnet = link.baseUrl;
  const lan = [...nearbyEndpoints(link.macKey), ...(link.lan ?? [])];
  const route = state._tag === "Ready" ? state.route : null;
  const latency = state._tag === "Ready" && state.latencyMs !== null ? ` · ${String(state.latencyMs)} ms` : "";

  const runTest = () => {
    if (tailnet === null) return;
    setTest({ _tag: "Testing" });
    void testTailnet(tailnet).then(setTest);
  };

  const word = test._tag === "Works" ? "Away works." : "Connection.";
  const wordTone: Tone = test._tag === "Works" ? "pulse" : "ink";
  const metaLine = route === null ? "not connected" : `${route === "lan" ? "Wi-Fi" : "Tailscale"}${latency} · in use`;
  const wifi = wifiValue(route, lan.length > 0);
  const away = tailnetValue(route, tailnet !== null);
  const testLine = test._tag === "Works" ? `${TEST_LINE.Works} · ${String(test.ms)} ms` : TEST_LINE[test._tag];

  return (
    <Screen
      top={
        <>
          <BackHeader parent="Record" onBack={() => navigation.goBack()} />
          <View className="gap-1 px-[22px] pb-3 pt-1">
            <Serif size="state" italic tone={wordTone} accessibilityRole="header">
              {word}
            </Serif>
            <Mono>{metaLine}</Mono>
          </View>
        </>
      }
    >
      <Section title="Routes">
        <Row
          plain
          label="Wi-Fi"
          detail={lan[0] === undefined ? "not on the Mac's Wi-Fi" : `${lan[0].host} · encrypted, pinned to this Mac`}
          value={wifi.value}
          valueTone={wifi.tone}
        />
        <Row
          plain
          label="Tailscale"
          detail={tailnet === null ? "away access is not set up" : hostOf(tailnet)}
          value={away.value}
          valueTone={away.tone}
        />
      </Section>

      <Section title="Away access">
        {tailnetSupported && tailnet !== null ? <BuiltInTailscale /> : null}
        <Step done={tailnet !== null} label="Mac is on Tailscale" detail={tailnet === null ? "On the Mac: Remote, then Tailscale" : hostOf(tailnet)} />
        <Step done={test._tag === "Works"} label="Tailscale on this phone" action="Get it" onPress={() => void Linking.openURL(TAILSCALE_STORE_URL)} />
        <Step
          done={test._tag === "Works"}
          label={link.owner === null || link.owner === undefined ? "Sign in to Tailscale" : `Sign in as ${link.owner}`}
          detail="the same account as the Mac"
          action="Open"
          onPress={() => void Linking.openURL(TAILSCALE_STORE_URL)}
        />
        <Step done={test._tag === "Works"} label="Test the route" detail={tailnet === null ? "after the Mac is set up" : "works on Wi-Fi too"} action={testLine} onPress={runTest} />
        {test._tag === "Works" ? <Mono className="px-[22px] pt-3">At home Vitals still uses Wi-Fi. It switches by itself.</Mono> : null}
      </Section>

      <View className="px-[22px] pt-6">
        <Button label="Check routes now" variant="line" block onPress={() => remote.connection.wake("manual")} />
      </View>
    </Screen>
  );
}
