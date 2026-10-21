import type { BottomTabNavigationProp } from "@react-navigation/bottom-tabs";
import { useNavigation } from "@react-navigation/native";
import type { ConnectionState } from "@vitals/client-runtime";
import { AlarmBanner, Row } from "@vitals/ui";
import { Linking, View } from "react-native";

import { AlertBanner } from "../../components/AlertBanner.tsx";
import { isPending, PendingOrder, secondsLeft } from "../../components/PendingOrder.tsx";
import { useRemote } from "../../connection/useRemote.ts";
import { TAILSCALE_STORE_URL } from "../../lib/links.ts";
import type { TabParams } from "../../navigation/types.ts";
import { useNow } from "../../state/useVitals.ts";
import { useStore } from "../../state/useStore.ts";

function BackoffBar({ state }: { readonly state: Extract<ConnectionState, { readonly _tag: "Backoff" }> }) {
  const remote = useRemote();
  const now = useNow(1000);
  return (
    <AlarmBanner
      level="medium"
      title="Connection lost."
      detail={`Retrying in ${secondsLeft(state.retryAt, now)} · attempt ${String(state.attempt)}`}
      action="Retry"
      onAction={() => remote.connection.wake("manual")}
    />
  );
}

const ROUTE_LABEL = { lan: "Wi-Fi", tailnet: "Tailscale" } as const;

function RouteFailures({ state }: { readonly state: Extract<ConnectionState, { readonly _tag: "Backoff" }> }) {
  const tailnetDown = state.failures.some((failure) => failure.kind === "tailnet");
  return (
    <View>
      {state.failures.map((failure) => (
        <Row key={failure.kind} plain label={ROUTE_LABEL[failure.kind]} detail={failure.reason} value="down" valueTone="alarmMedium" />
      ))}
      {tailnetDown ? <Row plain label="Open Tailscale" detail="Turn it on, then come back" onPress={() => void Linking.openURL(TAILSCALE_STORE_URL)} /> : null}
    </View>
  );
}

const SHOWN = 2;

function MoreAlarms({ count }: { readonly count: number }) {
  const navigation = useNavigation<BottomTabNavigationProp<TabParams>>();
  return <Row plain label={`${String(count)} more open in Alarms`} onPress={() => navigation.navigate("Alarms")} />;
}

export function ChartBanners() {
  const remote = useRemote();
  const alerts = useStore(remote.events.alerts);
  const pending = useStore(remote.events.receipts).filter(isPending);
  const state = useStore(remote.connection.state);
  return (
    <View>
      {state._tag === "Backoff" ? <BackoffBar state={state} /> : null}
      {state._tag === "Backoff" && state.failures.length > 0 ? <RouteFailures state={state} /> : null}
      {alerts.slice(0, SHOWN).map((alert) => (
        <AlertBanner key={alert.id} alert={alert} />
      ))}
      {alerts.length > SHOWN ? <MoreAlarms count={alerts.length - SHOWN} /> : null}
      {pending.slice(0, SHOWN).map((receipt) => (
        <PendingOrder key={receipt.id} receipt={receipt} />
      ))}
    </View>
  );
}
