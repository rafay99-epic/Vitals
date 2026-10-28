import type { Alert } from "@vitals/contracts";
import { formatClock } from "@vitals/shared";
import { AlarmBanner } from "@vitals/ui";

import { useRemote } from "../connection/useRemote.ts";
import { useScopes } from "../state/useScopes.ts";

export function AlertBanner({ alert, locked = false }: { readonly alert: Alert; readonly locked?: boolean | undefined }) {
  const remote = useRemote();
  const canOperate = useScopes().includes("operate");
  const blocked = locked || !canOperate;
  return (
    <AlarmBanner
      level={alert.severity === "critical" ? "high" : "medium"}
      title={`${alert.summary}.`}
      detail={`${alert.plan.summary} · since ${formatClock(alert.raisedAt)}`}
      action={blocked ? undefined : "Calm down"}
      onAction={blocked ? undefined : () => void remote.run({ _tag: "CalmDown", alertId: alert.id })}
    />
  );
}
