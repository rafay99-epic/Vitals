import type { Command, CommandReceipt } from "@vitals/contracts";
import { formatClock } from "@vitals/shared";
import { Countdown, HoldButton, Row, Screen, Section, Segmented, SlideToConfirm, TextButton } from "@vitals/ui";
import { useState } from "react";
import { Text, TextInput, View } from "react-native";

import { useRemote } from "../../connection/useRemote.ts";
import { thud, tick } from "../../lib/haptics";
import { useScopes } from "../../state/useScopes.ts";
import { useStore } from "../../state/useStore.ts";
import { StatusHeader } from "../live/StatusHeader.tsx";

const HOUR = 3_600_000;

const nextMorning = (): number => {
  const date = new Date();
  date.setDate(date.getHours() >= 8 ? date.getDate() + 1 : date.getDate());
  date.setHours(8, 0, 0, 0);
  return date.getTime();
};

const label = (kind: string): string =>
  ({ ShutDown: "Shut down", LogOut: "Log out", KeepAwake: "Keep awake", AllowSleep: "Allow sleep", DisplayOff: "Display off", OpenUrl: "Open link", ClipboardSet: "Send clipboard", CalmDown: "Calm down", UndoCalm: "Undo calm" })[kind] ?? kind;

export function ControlScreen() {
  const remote = useRemote();
  const receipts = useStore(remote.events.receipts);
  const keepAwake = useStore(remote.events.keepAwake);
  const scopes = useScopes();
  const [volume, setVolume] = useState<"0" | "0.25" | "0.5" | "0.75" | "1">("0.5");
  const [clip, setClip] = useState("");
  const [link, setLink] = useState("");
  const [macClipboard, setMacClipboard] = useState<string | null>(null);

  const run = (command: Command) => {
    tick();
    void remote.run(command);
  };

  const pending = receipts.filter((receipt): receipt is CommandReceipt & { readonly deadlineAt: number } => receipt.status === "pending" && receipt.deadlineAt !== null);

  return (
    <Screen>
      <StatusHeader />
      {pending.map((receipt) => (
        <Countdown key={receipt.id} title={label(receipt.kind)} deadline={receipt.deadlineAt} onCancel={() => void remote.cancel(receipt)} />
      ))}

      <Section title="Scenes">
        <View className="gap-2">
          <HoldButton
            label="Bedtime: display off, then sleep"
            onStart={tick}
            onCommit={() => {
              thud();
              void (async () => {
                await remote.run({ _tag: "AllowSleep" });
                await remote.run({ _tag: "DisplayOff" });
                await remote.run({ _tag: "Sleep", graceSeconds: 0 });
              })();
            }}
          />
          <TextButton
            label="Away: keep awake 4 h, display off"
            onPress={() =>
              void (async () => {
                await remote.run({ _tag: "KeepAwake", until: Date.now() + 4 * HOUR, display: false, whileProcess: null });
                await remote.run({ _tag: "DisplayOff" });
              })()
            }
          />
        </View>
      </Section>

      <Section title={keepAwake?.active === true ? `Keep awake · on${keepAwake.until === null ? "" : ` until ${formatClock(keepAwake.until)}`}` : "Keep awake"}>
        <View className="flex-row flex-wrap gap-2">
          <TextButton label="1 h" onPress={() => run({ _tag: "KeepAwake", until: Date.now() + HOUR, display: false, whileProcess: null })} />
          <TextButton label="4 h" onPress={() => run({ _tag: "KeepAwake", until: Date.now() + 4 * HOUR, display: false, whileProcess: null })} />
          <TextButton label="Until 8 AM" onPress={() => run({ _tag: "KeepAwake", until: nextMorning(), display: false, whileProcess: null })} />
          <TextButton label="Forever" onPress={() => run({ _tag: "KeepAwake", until: null, display: false, whileProcess: null })} />
          <TextButton label="Allow sleep" tone="accent" onPress={() => run({ _tag: "AllowSleep" })} disabled={keepAwake?.active !== true} />
        </View>
      </Section>

      <Section title="Power">
        <View className="gap-2">
          <View className="flex-row gap-2">
            <View className="flex-1">
              <TextButton label="Display off" onPress={() => run({ _tag: "DisplayOff" })} />
            </View>
            <View className="flex-1">
              <TextButton label="Lock" onPress={() => run({ _tag: "Lock" })} />
            </View>
          </View>
          <HoldButton label="Sleep" onStart={tick} onCommit={() => {
            thud();
            void remote.run({ _tag: "Sleep", graceSeconds: 0 });
          }} />
          {scopes.includes("destructive") ? (
            <>
              <SlideToConfirm label="restart" onConfirm={() => run({ _tag: "Restart", graceSeconds: 10 })} />
              <SlideToConfirm label="shut down" onConfirm={() => run({ _tag: "ShutDown", graceSeconds: 10 })} />
              <SlideToConfirm label="log out" onConfirm={() => run({ _tag: "LogOut", graceSeconds: 10 })} />
            </>
          ) : (
            <Text className="text-xs text-mute">Restart, shut down and log out need the destructive permission. Turn it on for this phone in Vitals on the Mac.</Text>
          )}
        </View>
      </Section>

      <Section title="Sound">
        <Segmented
          options={[
            { value: "0", label: "0" },
            { value: "0.25", label: "25" },
            { value: "0.5", label: "50" },
            { value: "0.75", label: "75" },
            { value: "1", label: "100" },
          ]}
          value={volume}
          onChange={(next) => {
            setVolume(next);
            run({ _tag: "SetVolume", level: Number(next) });
          }}
        />
        <View className="mt-2 flex-row gap-2">
          <View className="flex-1">
            <TextButton label="Mute" onPress={() => run({ _tag: "SetMuted", muted: true })} />
          </View>
          <View className="flex-1">
            <TextButton label="Unmute" onPress={() => run({ _tag: "SetMuted", muted: false })} />
          </View>
          <View className="flex-1">
            <TextButton label="Locate" onPress={() => run({ _tag: "Locate" })} />
          </View>
        </View>
      </Section>

      <Section title="Send to Mac">
        <TextInput
          value={clip}
          onChangeText={setClip}
          placeholder="Text for the Mac clipboard"
          placeholderTextColor="#6b6b6b"
          multiline
          className="min-h-11 border border-line px-3 py-2 text-[15px] text-ink"
        />
        <View className="mt-2 flex-row gap-2">
          <View className="flex-1">
            <TextButton label="Copy to Mac" disabled={clip.length === 0} onPress={() => run({ _tag: "ClipboardSet", text: clip })} />
          </View>
          <View className="flex-1">
            <TextButton
              label="Read Mac clipboard"
              disabled={!scopes.includes("clipboard")}
              onPress={() =>
                void remote.connection.call((client) => client["clipboard.get"]({})).then((result) => {
                  if (result.ok) setMacClipboard(result.value.text ?? "(empty)");
                  else remote.show(result.error.message, "bad");
                })
              }
            />
          </View>
        </View>
        {macClipboard === null ? null : <Text selectable className="mt-2 font-mono text-xs text-dim">{macClipboard}</Text>}
        <TextInput
          value={link}
          onChangeText={setLink}
          placeholder="https:// link to open on the Mac"
          placeholderTextColor="#6b6b6b"
          autoCapitalize="none"
          keyboardType="url"
          className="mt-3 min-h-11 border border-line px-3 text-[15px] text-ink"
        />
        <View className="mt-2">
          <TextButton label="Open on Mac" disabled={!/^https?:\/\/\S+$/.test(link)} onPress={() => run({ _tag: "OpenUrl", url: link })} />
        </View>
      </Section>

      <Section title="Recent">
        {receipts.length === 0 ? <Text className="text-sm text-mute">No commands yet.</Text> : null}
        {receipts.slice(0, 12).map((receipt) => (
          <Row
            key={receipt.id}
            label={label(receipt.kind)}
            detail={receipt.error ?? formatClock(receipt.createdAt)}
            value={receipt.status}
            tone={receipt.status === "failed" || receipt.status === "rejected" ? "bad" : receipt.status === "done" ? "ok" : "dim"}
          />
        ))}
      </Section>
    </Screen>
  );
}
