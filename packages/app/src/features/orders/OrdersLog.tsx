import { formatClock } from "@vitals/shared";
import { EmptyState, Row, Section } from "@vitals/ui";

import { useRemote } from "../../connection/useRemote.ts";
import { useStore } from "../../state/useStore.ts";
import { orderLabel, STATUS_TONE } from "../../state/commands.ts";

const SHOWN = 20;

export function OrdersLog() {
  const receipts = useStore(useRemote().events.receipts);
  return (
    <Section title="Log" trailing="recent">
      {receipts.length === 0 ? <EmptyState title="No commands yet." detail="Orders you send show here with the Mac's answer." /> : null}
      {receipts.slice(0, SHOWN).map((receipt) => (
        <Row
          key={receipt.id}
          label={orderLabel(receipt.kind)}
          detail={receipt.error === null ? formatClock(receipt.createdAt) : `${formatClock(receipt.createdAt)} · ${receipt.error}`}
          value={receipt.status}
          valueTone={STATUS_TONE[receipt.status]}
        />
      ))}
    </Section>
  );
}
