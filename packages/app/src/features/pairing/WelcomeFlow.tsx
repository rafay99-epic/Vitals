import { Button, Mono, Row, Screen, Section, Serif } from "@vitals/ui";
import { useEffect, useState } from "react";
import { Platform, View } from "react-native";

import { sessions } from "../../connection/session.ts";
import { useRemote } from "../../connection/useRemote.ts";
import { hostOf } from "../../lib/host.ts";
import { notificationPermission } from "../../notifications/alerts";
import type { PermissionState } from "../../notifications/permission.ts";
import { scopeLine } from "../../state/commands.ts";
import { useScopes } from "../../state/useScopes.ts";
import { useStore } from "../../state/useStore.ts";
import { AlertsScreen } from "./AlertsScreen.tsx";
import { FirstBeat } from "./FirstBeat.tsx";

const ALERTS: Record<PermissionState, string> = { granted: "on", prompt: "ask next", denied: "off", unsupported: "not here" };

export function WelcomeFlow() {
  const remote = useRemote();
  const state = useStore(remote.connection.state);
  const scopes = useScopes();
  const [permission, setPermission] = useState<PermissionState | null>(null);
  const [step, setStep] = useState<"admitted" | "alerts">("admitted");
  const finish = () => sessions.finishWelcome();

  useEffect(() => {
    void notificationPermission().then(setPermission);
  }, []);

  if (step === "alerts") return <AlertsScreen onDone={finish} />;

  const mac = state._tag === "Ready" ? state.hello.mac : null;
  const next = () => (permission === "prompt" ? setStep("alerts") : finish());

  return (
    <Screen>
      <View className="gap-2 px-[22px] pt-10">
        <Serif size="hero" italic tone="pulse" accessibilityRole="header">
          Admitted.
        </Serif>
        <Mono>{mac === null ? hostOf(remote.credentials.baseUrl) : `${mac.name} · ${mac.chip} · ${mac.os}`}</Mono>
      </View>
      <View className="my-6">
        <FirstBeat />
      </View>
      <Section title="This device">
        <Row plain label="Scope" value={scopeLine(scopes)} />
        <Row plain label="Alerts" value={permission === null ? "--" : ALERTS[permission]} />
        <Row plain label="Session" value={Platform.OS === "web" ? "in a secure cookie" : "in the keychain"} />
      </Section>
      <View className="px-[22px] pt-8">
        <Button label="Open the Chart" block disabled={permission === null} onPress={next} />
      </View>
    </Screen>
  );
}
