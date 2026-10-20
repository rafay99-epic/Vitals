import { useFocusEffect } from "@react-navigation/native";
import type { AppsSnapshot, RunningApp } from "@vitals/contracts";
import { formatClock } from "@vitals/shared";
import { Row, Screen, Section, TextButton, useActionMenu } from "@vitals/ui";
import { useCallback, useState } from "react";
import { Text, TextInput, View } from "react-native";

import { sessions } from "../../connection/session.ts";
import { useRemote } from "../../connection/useRemote.ts";
import { useScopes } from "../../state/useScopes.ts";
import { useStore } from "../../state/useStore.ts";

export function MoreScreen() {
  const remote = useRemote();
  const state = useStore(remote.connection.state);
  const [apps, setApps] = useState<AppsSnapshot | null>(null);
  const [bundleId, setBundleId] = useState("");
  const scopes = useScopes();
  const destructive = scopes.includes("destructive");
  const [menuElement, openMenu] = useActionMenu();

  const refresh = useCallback(() => {
    void remote.connection.call((client) => client["apps.list"]({})).then((result) => {
      if (result.ok) setApps(result.value);
    });
  }, [remote]);

  useFocusEffect(refresh);

  const appMenu = (app: RunningApp) => {
    const ref = { pid: app.pid, bundleId: app.bundleId };
    openMenu({
      title: app.name,
      detail: app.bundleId ?? `pid ${app.pid}`,
      actions: [
        { label: "Quit", onPress: () => void remote.run({ _tag: "QuitApp", app: ref }).then(refresh) },
        { label: "Hide", onPress: () => void remote.run({ _tag: "HideApp", app: ref }) },
        ...(destructive ? [{ label: "Force quit", tone: "bad" as const, onPress: () => void remote.run({ _tag: "ForceQuitApp", app: ref }).then(refresh) }] : []),
      ],
    });
  };

  const mac = state._tag === "Ready" ? state.hello.mac : null;

  return (
    <Screen>
      {menuElement}
      <Section title="Mac">
        <Row label="Name" value={mac?.name ?? "--"} />
        <Row label="Model" value={mac === null ? "--" : `${mac.chip} · ${mac.model}`} />
        <Row label="macOS" value={mac?.os ?? "--"} />
        <Row label="Vitals" value={mac === null ? "--" : `${mac.vitalsVersion} (${mac.channel})`} />
        <Row label="Address" detail={remote.credentials.baseUrl} />
      </Section>

      <Section title="Emulators" trailing={<TextButton label="Refresh" onPress={refresh} />}>
        {(apps?.emulators ?? []).length === 0 ? <Text className="text-sm text-mute">None running.</Text> : null}
        {(apps?.emulators ?? []).map((emulator) => (
          <Row
            key={emulator.id}
            label={emulator.name}
            detail={`${emulator.kind} · ${emulator.id}`}
            value={destructive ? "Stop" : undefined}
            tone="bad"
            {...(destructive ? { onPress: () => void remote.run({ _tag: "StopEmulator", kind: emulator.kind, id: emulator.id }).then(refresh) } : {})}
          />
        ))}
      </Section>

      <Section title="Running apps">
        {(apps?.running ?? []).map((app) => (
          <Row key={app.pid} label={app.name} detail={app.active ? "frontmost" : app.hidden ? "hidden" : undefined} onPress={() => appMenu(app)} />
        ))}
        <TextInput
          value={bundleId}
          onChangeText={setBundleId}
          placeholder="Launch by bundle id, e.g. com.apple.Safari"
          placeholderTextColor="#6b6b6b"
          autoCapitalize="none"
          autoCorrect={false}
          className="mt-3 min-h-11 border border-line px-3 font-mono text-sm text-ink"
        />
        <View className="mt-2">
          <TextButton label="Launch" disabled={bundleId.length === 0} onPress={() => void remote.run({ _tag: "LaunchApp", bundleId }).then(refresh)} />
        </View>
      </Section>

      <Section title="This phone">
        <Row label="Permissions" value={scopes.join(", ")} />
        <Row label="Paired" value={formatClock(remote.credentials.pairedAt)} />
        <View className="mt-3">
          <TextButton
            label="Unpair"
            tone="bad"
            onPress={() =>
              openMenu({
                title: "Unpair this phone?",
                detail: "You will need a new code from the Mac.",
                actions: [{ label: "Unpair", tone: "bad", onPress: () => void sessions.forget() }],
              })
            }
          />
        </View>
      </Section>
    </Screen>
  );
}
