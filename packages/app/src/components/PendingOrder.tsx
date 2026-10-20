import type { CommandReceipt } from "@vitals/contracts";
import { AlarmBanner } from "@vitals/ui";

import { useRemote } from "../connection/useRemote.ts";
import { orderLabel } from "../state/commands.ts";
import { useNow } from "../state/useVitals.ts";

export type Pending = CommandReceipt & { readonly deadlineAt: number };

export const isPending = (receipt: CommandReceipt): receipt is Pending => receipt.status === "pending" && receipt.deadlineAt !== null;

export const secondsLeft = (until: number, now: number): string => `${String(Math.max(0, Math.ceil((until - now) / 1000)))} s`;

export function PendingOrder({ receipt }: { readonly receipt: Pending }) {
  const remote = useRemote();
  const now = useNow(1000);
  return (
    <AlarmBanner
      level="medium"
      title={`${orderLabel(receipt.kind)} in ${secondsLeft(receipt.deadlineAt, now)}.`}
      detail="Cancel stops it on the Mac."
      action="Cancel"
      onAction={() => void remote.cancel(receipt)}
    />
  );
}
