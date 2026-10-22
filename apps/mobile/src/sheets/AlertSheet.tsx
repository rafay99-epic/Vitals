import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import type { Alert } from "@vitals/contracts";
import { formatClock } from "@vitals/shared";
import { StyleSheet, View } from "react-native";

import { ALERT_TITLE, send, useAccess } from "../lib/remote.ts";
import { BigButton, color, sheet, SheetCancel, SheetHeader, SheetNote, T } from "../ui/index.ts";

/** Asks the Mac to calm things down for one alert. Lowers priority; nothing is closed. */
export const calm = (remote: ReturnType<typeof useRemote>, alert: Alert | null) =>
  void send(remote, { _tag: "CalmDown", alertId: alert?.id ?? null }, alert === null ? "Calming the Mac" : alert.plan.summary, {
    command: { _tag: "UndoCalm" },
    done: "Back to normal priority",
  });

function OtherAlerts({ alerts }: { readonly alerts: ReadonlyArray<Alert> }) {
  if (alerts.length === 0) return null;
  return (
    <View style={styles.others}>
      {alerts.map((alert) => (
        <T key={alert.id} v="small" color={alert.severity === "critical" ? color.red : color.orange}>
          {`▲ ${ALERT_TITLE[alert.rule]} · ${alert.summary}`}
        </T>
      ))}
    </View>
  );
}

/** Opened from the alert line on Home. Explains the first alert and offers the fix. */
export function AlertSheet() {
  const remote = useRemote();
  const access = useAccess();
  const alerts = useStore(remote.events.alerts);
  const calmed = useStore(remote.events.calmed);
  const first = alerts[0];
  if (first === undefined) {
    return (
      <>
        <SheetHeader title="All clear" detail="No alerts right now." />
        <SheetCancel label="Close" />
      </>
    );
  }
  return (
    <>
      <SheetHeader title={ALERT_TITLE[first.rule]} detail={`${first.summary} · since ${formatClock(first.raisedAt)}`} />
      <SheetNote>{`Calming will ${first.plan.summary.charAt(0).toLowerCase()}${first.plan.summary.slice(1)}. Nothing gets closed, and you can undo it.`}</SheetNote>
      {calmed ? <SheetNote>Calmed a moment ago. The Mac clears this alert once the numbers settle.</SheetNote> : null}
      {access.operate ? (
        <BigButton
          label={calmed ? "Calm again" : "Calm it down"}
          onPress={() => {
            sheet.close();
            calm(remote, first);
          }}
        />
      ) : (
        <SheetNote>This phone can only watch. Turn on control for it in Vitals on the Mac.</SheetNote>
      )}
      <OtherAlerts alerts={alerts.slice(1)} />
      <SheetCancel label="Not now" />
    </>
  );
}

const styles = StyleSheet.create({
  others: { paddingHorizontal: 20, paddingTop: 8, gap: 4 },
});
