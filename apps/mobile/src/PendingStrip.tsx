import { isPending, type Pending, secondsLeft } from "@vitals/app/components/PendingOrder.tsx";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { orderLabel } from "@vitals/app/state/commands.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";

import { useAccess } from "./lib/remote.ts";
import { Strip, toast } from "./ui/index.ts";

const VERB: Readonly<Record<string, string>> = {
  ShutDown: "Shutting down",
  Restart: "Restarting",
  LogOut: "Logging out",
  Sleep: "Going to sleep",
};

function Countdown({ receipt }: { readonly receipt: Pending }) {
  const remote = useRemote();
  const access = useAccess();
  const now = useNow(1000);
  const text = `${VERB[receipt.kind] ?? orderLabel(receipt.kind)} in ${secondsLeft(receipt.deadlineAt, now)}`;
  return access.operate ? (
    <Strip tone="warn" text={text} action="Cancel" onAction={() => void remote.cancel(receipt).then((ok) => ok && toast.show("Cancelled"))} />
  ) : (
    <Strip tone="warn" text={text} />
  );
}

/** Pinned above the dock while timed orders (shut down, restart) count down on the Mac, one strip each. */
export function PendingStrip() {
  const pending = useStore(useRemote().events.receipts).filter(isPending);
  return pending.map((receipt) => <Countdown key={receipt.id} receipt={receipt} />);
}
