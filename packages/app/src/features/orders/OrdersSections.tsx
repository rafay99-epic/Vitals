import type { Command, CommandReceipt, KeepAwakeState } from "@vitals/contracts";
import { BeatSwitch, Chips, HoldRow, Row, Section, Slider } from "@vitals/ui";
import { useState } from "react";
import { View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { haptics } from "../../lib/haptics";
import { useStore } from "../../state/useStore.ts";
import { type Discharge, DISCHARGE } from "./ConsentSheet.tsx";
import { AWAY_MS, STAY_OPTIONS, type StayAwake, stayUntil } from "./labels.ts";

export interface SectionProps {
  readonly locked: boolean;
  readonly run: (command: Command) => Promise<CommandReceipt | null>;
}

const landed = (receipt: CommandReceipt | null): boolean => receipt !== null && receipt.status !== "failed" && receipt.status !== "rejected";

const runInOrder = async (run: SectionProps["run"], commands: ReadonlyArray<Command>): Promise<void> => {
  for (const command of commands) {
    if (!landed(await run(command))) return;
  }
};

const commit = (run: SectionProps["run"], commands: ReadonlyArray<Command>) => () => {
  haptics.success();
  void runInOrder(run, commands);
};

export function NowSection({ locked, run }: SectionProps) {
  return (
    <View>
      <HoldRow label="Rest" hint={"hold to sleep\ndisplay goes first"} locked={locked} onStart={haptics.soft} onCommit={commit(run, [{ _tag: "Sleep", graceSeconds: 0 }])} />
      <HoldRow label="Lights out" hint="display off · Mac stays awake" compact locked={locked} onStart={haptics.soft} onCommit={commit(run, [{ _tag: "DisplayOff" }])} />
      <HoldRow label="Lock" hint="back to the login screen" compact locked={locked} onStart={haptics.soft} onCommit={commit(run, [{ _tag: "Lock" }])} />
    </View>
  );
}

const selectedStay = (keepAwake: KeepAwakeState | null, chosen: StayAwake | null): StayAwake | null => {
  if (keepAwake?.active !== true) return null;
  return keepAwake.until === null ? "forever" : chosen;
};

export function StayAwakeSection({ locked, run }: SectionProps) {
  const keepAwake = useStore(useRemote().events.keepAwake);
  const [chosen, setChosen] = useState<StayAwake | null>(null);
  const active = keepAwake?.active === true;
  const selected = selectedStay(keepAwake, chosen);

  const choose = (value: StayAwake) => {
    haptics.select();
    setChosen(value);
    void run({ _tag: "KeepAwake", until: stayUntil[value](Date.now()), display: false, whileProcess: null });
  };

  return (
    <Section title="Stay awake" trailing={active ? "on" : "off"}>
      <View className="border-t border-line px-[22px] py-1.5">
        <Chips options={STAY_OPTIONS} value={selected} onChange={choose} disabled={locked} />
      </View>
      <Row label="Allow sleep" detail="end stay awake now" locked={locked || !active} onPress={() => void run({ _tag: "AllowSleep" })} />
    </Section>
  );
}

export function SoundSection({ locked, run }: SectionProps) {
  const [volume, setVolume] = useState(0.5);
  const [muted, setMuted] = useState(false);
  return (
    <Section title="Sound" trailing="last sent from this device">
      <View className="min-h-14 flex-row items-center border-t border-line px-[22px]">
        <Slider
          value={volume}
          disabled={locked}
          accessibilityLabel="Mac volume"
          format={(level) => String(Math.round(level * 100))}
          onCommit={(level) => {
            setVolume(level);
            void run({ _tag: "SetVolume", level });
          }}
        />
      </View>
      <Row
        label="Mute"
        locked={locked}
        trailing={
          <BeatSwitch
            value={muted}
            disabled={locked}
            accessibilityLabel="Mute the Mac"
            onChange={(next) => {
              haptics.light();
              setMuted(next);
              void run({ _tag: "SetMuted", muted: next });
            }}
          />
        }
      />
    </Section>
  );
}

export function HandOverSection({ locked, run, onClipboard, onOpen }: SectionProps & { readonly onClipboard: () => void; readonly onOpen: () => void }) {
  return (
    <Section title="Hand over">
      <Row label="Clipboard" detail="copy to the Mac or read it" locked={locked} onPress={onClipboard} />
      <Row label="Open on Mac" detail="a link, in the default browser" locked={locked} onPress={onOpen} />
      <Row label="Locate" detail="plays a sound on the Mac" locked={locked} onPress={() => void run({ _tag: "Locate" })} />
    </Section>
  );
}

export function ScenesSection({ locked, run }: SectionProps) {
  return (
    <Section title="Scenes">
      <HoldRow
        label="Bedtime"
        hint="display off, then sleep"
        compact
        locked={locked}
        onStart={haptics.soft}
        onCommit={commit(run, [{ _tag: "AllowSleep" }, { _tag: "DisplayOff" }, { _tag: "Sleep", graceSeconds: 0 }])}
      />
      <HoldRow
        label="Away"
        hint="stay awake 4 h, display off"
        compact
        locked={locked}
        onStart={haptics.soft}
        onCommit={() => {
          haptics.success();
          void runInOrder(run, [{ _tag: "KeepAwake", until: Date.now() + AWAY_MS, display: false, whileProcess: null }, { _tag: "DisplayOff" }]);
        }}
      />
    </Section>
  );
}

const DISCHARGE_ORDER: ReadonlyArray<Discharge> = ["Restart", "LogOut", "ShutDown"];

export function DischargeSection({ allowed, locked, onPick }: { readonly allowed: boolean; readonly locked: boolean; readonly onPick: (order: Discharge) => void }) {
  if (!allowed) {
    return (
      <Section title="Discharge" trailing="needs consent">
        <Row label="Restart, log out, shut down" detail="Off for this device. Turn on Destructive for it in Vitals on the Mac." locked />
      </Section>
    );
  }
  return (
    <Section title="Discharge" trailing="needs consent">
      {DISCHARGE_ORDER.map((order) => (
        <Row key={order} label={DISCHARGE[order].label} tone="press" locked={locked} onPress={() => onPick(order)} />
      ))}
    </Section>
  );
}
