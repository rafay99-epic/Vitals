import { AlarmBanner } from "@vitals/ui";

import { useRemote } from "../connection/useRemote.ts";
import { orderLabel } from "../state/commands.ts";
import { useScopes } from "../state/useScopes.ts";
import { isOverdue, type Pending, secondsLeft } from "../state/countdown.ts";
import { useNow } from "../state/useVitals.ts";

export function PendingOrder({ receipt }: { readonly receipt: Pending }) {
  const remote = useRemote();
  const now = useNow(1000);
  const canCancel = useScopes().includes("operate");
  if (isOverdue(receipt, now)) return null;
  return (
    <AlarmBanner
      level="medium"
      title={`${orderLabel(receipt.kind)} in ${secondsLeft(receipt.deadlineAt, now)}.`}
      detail={canCancel ? "Cancel stops it on the Mac." : "Only a device that can control the Mac can cancel it."}
      action={canCancel ? "Cancel" : undefined}
      onAction={canCancel ? () => void remote.cancel(receipt) : undefined}
    />
  );
}
