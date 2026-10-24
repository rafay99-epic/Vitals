import type { Command, KeepAwakeState } from "@vitals/contracts";
import { formatClock } from "@vitals/shared";
import { AlarmBanner, Columns, Screen } from "@vitals/ui";
import { useState } from "react";

import { PendingOrder } from "../../components/PendingOrder.tsx";
import { isPending } from "../../state/countdown.ts";
import { TabHeader } from "../../components/TabHeader.tsx";
import { useRemote } from "../../connection/useRemote.ts";
import { useScopes } from "../../state/useScopes.ts";
import { useStore } from "../../state/useStore.ts";
import { ClipboardSheet } from "./ClipboardSheet.tsx";
import { ConsentSheet, type Discharge } from "./ConsentSheet.tsx";
import { DischargeSection, HandOverSection, NowSection, ScenesSection, SoundSection, StayAwakeSection } from "./OrdersSections.tsx";
import { OpenSheet } from "./OpenSheet.tsx";
import { OrdersLog } from "./OrdersLog.tsx";

const awakeMeta = (keepAwake: KeepAwakeState | null): string => {
  if (keepAwake?.active !== true) return "awake · sleeps on its own schedule";
  return keepAwake.until === null ? "keeping awake · until you allow sleep" : `keeping awake · until ${formatClock(keepAwake.until)}`;
};

type Sheet = "clipboard" | "open" | null;

export function OrdersScreen() {
  const remote = useRemote();
  const scopes = useScopes();
  const keepAwake = useStore(remote.events.keepAwake);
  const pending = useStore(remote.events.receipts).filter(isPending);
  const [sheet, setSheet] = useState<Sheet>(null);
  const [discharge, setDischarge] = useState<Discharge | null>(null);
  const locked = !scopes.includes("operate");
  const run = (command: Command) => remote.run(command);
  const sections = { locked, run };

  return (
    <Screen>
      <TabHeader title="Orders." meta={awakeMeta(keepAwake)} metaTone={keepAwake?.active === true ? "temp" : "dim"} />
      {locked ? <AlarmBanner level="low" title="This device cannot control the Mac." detail="Read only. Turn on Operate for it in Vitals on the Mac." /> : null}
      {pending.map((receipt) => (
        <PendingOrder key={receipt.id} receipt={receipt} />
      ))}
      <Columns
        main={
          <>
            <NowSection {...sections} />
            <StayAwakeSection {...sections} />
            <SoundSection {...sections} />
            <HandOverSection {...sections} canRead={scopes.includes("clipboard")} onClipboard={() => setSheet("clipboard")} onOpen={() => setSheet("open")} />
            <ScenesSection {...sections} />
            <DischargeSection allowed={scopes.includes("destructive")} onPick={setDischarge} />
          </>
        }
        side={<OrdersLog />}
      />
      <ClipboardSheet visible={sheet === "clipboard"} canRead={scopes.includes("clipboard")} canWrite={!locked} onClose={() => setSheet(null)} />
      <OpenSheet visible={sheet === "open"} onClose={() => setSheet(null)} />
      <ConsentSheet order={discharge} onClose={() => setDischarge(null)} />
    </Screen>
  );
}
