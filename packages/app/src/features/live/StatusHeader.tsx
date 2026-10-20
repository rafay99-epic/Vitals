import { formatClock } from "@vitals/shared";
import { Banner } from "@vitals/ui";
import { Text, View } from "react-native";

import { sessions } from "../../connection/session.ts";
import { useRemote } from "../../connection/useRemote.ts";
import { useStore } from "../../state/useStore.ts";

export function StatusHeader() {
  const remote = useRemote();
  const state = useStore(remote.connection.state);
  const asleepSince = useStore(remote.events.asleepSince);
  const poweringOff = useStore(remote.events.poweringOff);
  const keepAwake = useStore(remote.events.keepAwake);
  const alerts = useStore(remote.events.alerts);
  const toast = useStore(remote.toast);

  const mac = state._tag === "Ready" ? state.hello.mac : null;
  const line = (() => {
    if (poweringOff !== null) return { text: `Powering off since ${formatClock(poweringOff)}`, tone: "text-warn" };
    if (asleepSince !== null && state._tag !== "Ready") return { text: `Asleep since ${formatClock(asleepSince)}`, tone: "text-dim" };
    switch (state._tag) {
      case "Ready":
        return mac === null ? { text: "Vitals is not running on the Mac", tone: "text-warn" } : { text: "Live", tone: "text-ok" };
      case "Connecting":
        return { text: state.attempt > 1 ? `Connecting, attempt ${state.attempt}` : "Connecting", tone: "text-dim" };
      case "Backoff":
        return { text: `${state.reason}. Retry ${state.attempt} at ${formatClock(state.retryAt)}`, tone: "text-warn" };
      case "Suspended":
        return { text: "Paused in background", tone: "text-dim" };
      case "Revoked":
        return { text: "This phone was removed on the Mac", tone: "text-bad" };
      case "Incompatible":
        return { text: "Update the app or Vitals to the same version", tone: "text-bad" };
      case "Idle":
        return { text: "Starting", tone: "text-dim" };
    }
  })();

  return (
    <View className="pt-3">
      <View className="flex-row items-baseline justify-between">
        <Text className="text-2xl font-semibold text-ink" numberOfLines={1}>
          {mac?.name ?? "Your Mac"}
        </Text>
        <Text className={`font-mono text-xs ${line.tone}`}>{line.text}</Text>
      </View>
      {mac === null ? null : (
        <Text className="mt-0.5 font-mono text-[11px] text-mute">{`${mac.chip} · ${mac.os} · Vitals ${mac.vitalsVersion}`}</Text>
      )}
      {keepAwake?.active === true ? (
        <Text className="mt-2 font-mono text-xs text-accent">
          {keepAwake.until === null ? "Keeping awake" : `Keeping awake until ${formatClock(keepAwake.until)}`}
        </Text>
      ) : null}
      {state._tag === "Revoked" ? <Banner text="Pair again to reconnect." tone="bad" action="Pair" onAction={() => void sessions.forget()} /> : null}
      {alerts.map((alert) => (
        <Banner
          key={alert.id}
          text={alert.summary}
          tone={alert.severity === "critical" ? "bad" : "warn"}
          action="Calm down"
          onAction={() => void remote.run({ _tag: "CalmDown", alertId: alert.id })}
        />
      ))}
      {toast === null ? null : <Banner text={toast.message} tone={toast.tone} />}
    </View>
  );
}
