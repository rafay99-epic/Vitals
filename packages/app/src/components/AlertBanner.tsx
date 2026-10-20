import type { Alert } from "@vitals/contracts";
import { formatClock } from "@vitals/shared";
import { AlarmBanner } from "@vitals/ui";

import { useRemote } from "../connection/useRemote.ts";

export function AlertBanner({ alert, locked = false }: { readonly alert: Alert; readonly locked?: boolean | undefined }) {
  const remote = useRemote();
  return (
    <AlarmBanner
      level={alert.severity === "critical" ? "high" : "medium"}
      title={`${alert.summary}.`}
      detail={`${alert.plan.summary} · since ${formatClock(alert.raisedAt)}`}
      action={locked ? undefined : "Calm down"}
      onAction={locked ? undefined : () => void remote.run({ _tag: "CalmDown", alertId: alert.id })}
    />
  );
}
