import type { ConnectionState } from "@vitals/client-runtime";
import { PROTOCOL_VERSION } from "@vitals/contracts";
import { Button, Mono, Row, Sans, Screen, ScreenHeader } from "@vitals/ui";
import { View } from "react-native";

import { sessions } from "../../connection/session.ts";
import { CLIENT_VERSION } from "../../state/remote.ts";

export type BrokenLink = Extract<ConnectionState, { readonly _tag: "Revoked" | "Incompatible" }>;

export const isBroken = (state: ConnectionState): state is BrokenLink => state._tag === "Revoked" || state._tag === "Incompatible";

function Removed() {
  return (
    <View className="gap-4 px-[22px] pt-10">
      <View className="mb-4 h-px bg-line3" />
      <Sans tone="ink2">This phone was removed on the Mac. Pair again to reconnect.</Sans>
      <Mono>Session and alarms are cleared from this device when you pair again.</Mono>
      <View className="pt-6">
        <Button label="Pair again" block onPress={() => void sessions.forget()} />
      </View>
    </View>
  );
}

function OutOfStep({ serverProtocol }: { readonly serverProtocol: number | null }) {
  return (
    <View className="pt-10">
      <View className="gap-4 px-[22px] pb-6">
        <Sans tone="ink2">Update the app or Vitals to the same version.</Sans>
      </View>
      <Row label="This app" value={`${CLIENT_VERSION} · protocol ${String(PROTOCOL_VERSION)}`} plain />
      <Row label="Vitals on the Mac" value={serverProtocol === null ? "protocol unknown" : `protocol ${String(serverProtocol)}`} valueTone="alarmMedium" plain />
    </View>
  );
}

const BROKEN: Record<BrokenLink["_tag"], { readonly link: string; readonly word: string }> = {
  Revoked: { link: "removed", word: "Removed." },
  Incompatible: { link: "out of step", word: "Out of step." },
};

export function LinkState({ state, who }: { readonly state: BrokenLink; readonly who: string }) {
  return (
    <Screen>
      <ScreenHeader who={who} link={BROKEN[state._tag].link} linkTone="off" word={BROKEN[state._tag].word} />
      {state._tag === "Revoked" ? <Removed /> : <OutOfStep serverProtocol={state.serverProtocol} />}
    </Screen>
  );
}
