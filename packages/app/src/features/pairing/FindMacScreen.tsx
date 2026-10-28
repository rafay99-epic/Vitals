import { type FoundMac, type LocalNetworkPermission, requestLocalNetwork } from "@vitals/discovery";
import { Button, Mono, Row, Section, Serif } from "@vitals/ui";
import { type ReactNode, useEffect, useState } from "react";
import { View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { FirstBeat } from "../../components/FirstBeat.tsx";
import { macKeyOf, nearby } from "../../connection/nearby.ts";
import { type NearbyWait, sessions } from "../../connection/session.ts";
import { haptics } from "../../lib/haptics";
import { channel } from "../../lib/variant";
import { useStore } from "../../state/useStore.ts";

const nameOf = (mac: FoundMac): string => mac.txt["n"] ?? mac.name;

/** Dev phones pair with Dev Macs; Stable and Nightly phones with Stable and Nightly Macs. */
const sameChannel = (mac: FoundMac): boolean => (mac.txt["c"] === "dev") === (channel === "dev");

const pairable = (macs: ReadonlyArray<FoundMac>): ReadonlyArray<FoundMac> => macs.filter((mac) => macKeyOf(mac) !== null && sameChannel(mac));

function Waiting({ wait }: { readonly wait: NearbyWait }) {
  return (
    <>
      <View className="gap-2 px-[22px] pt-10">
        <Serif size="state" italic accessibilityRole="header">
          Waiting for the Mac.
        </Serif>
        <Mono accessibilityLiveRegion="polite">{wait.code === null ? wait.name : `${wait.name} · code ${wait.code}`}</Mono>
      </View>
      <View className="my-6">
        <FirstBeat />
      </View>
      <Mono className="px-[22px]">A notification is on your Mac. Allow it there.</Mono>
      <View className="mt-auto px-[22px]">
        <Button label="Cancel" variant="line" block onPress={() => sessions.cancelPairNearby()} />
      </View>
    </>
  );
}

function Found({ mac, others, onPick }: { readonly mac: FoundMac; readonly others: ReadonlyArray<FoundMac>; readonly onPick: (mac: FoundMac) => void }) {
  const [showAll, setShowAll] = useState(false);
  return (
    <>
      <View className="gap-2 px-[22px] pt-10">
        <Serif size="state" italic tone="pulse" accessibilityRole="header">
          Found it.
        </Serif>
        <Mono>on this Wi-Fi</Mono>
      </View>
      <View className="gap-1 px-[22px] pt-6">
        <Serif size="m">{nameOf(mac)}</Serif>
        <Mono>{`Vitals · Remote on · ${mac.host}`}</Mono>
      </View>
      {showAll ? (
        <Section title="Also on this Wi-Fi">
          {others.map((other) => (
            <Row key={other.name} label={nameOf(other)} detail={other.host} onPress={() => onPick(other)} />
          ))}
        </Section>
      ) : null}
      <View className="mt-auto gap-2 px-[22px]">
        <Button label="Connect" block onPress={() => onPick(mac)} />
        {others.length === 0 || showAll ? null : (
          <Button label={`Not this one? ${String(others.length)} more on this Wi-Fi`} variant="text" onPress={() => setShowAll(true)} />
        )}
      </View>
    </>
  );
}

function Looking({ permission }: { readonly permission: LocalNetworkPermission | null }) {
  return (
    <>
      <View className="gap-2 px-[22px] pt-10">
        <Serif size="state" italic accessibilityRole="header">
          Looking.
        </Serif>
        <Mono>{permission === "denied" ? "Vitals is not allowed on your local network" : "Vitals looks on this Wi-Fi. Nothing leaves your network."}</Mono>
      </View>
      <View className="my-6">
        <FirstBeat />
      </View>
      <Mono className="px-[22px]">
        {permission === "denied"
          ? "Allow Local Network for Vitals in Settings, or pair with the QR on the Mac."
          : "Not here? Open Vitals on the Mac and turn on Remote."}
      </Mono>
      <View className="flex-1" />
    </>
  );
}

/** `onWhy` opens the app's connection check from under a pairing error, when the app has one. */
export function FindMacScreen({ onScan, onWhy }: { readonly onScan: () => void; readonly onWhy?: () => void }) {
  const insets = useSafeAreaInsets();
  const macs = pairable(useStore(nearby));
  const pairing = useStore(sessions.pairing);
  const [permission, setPermission] = useState<LocalNetworkPermission | null>(null);

  useEffect(() => {
    void requestLocalNetwork().then(setPermission);
  }, []);

  const pick = (mac: FoundMac) => {
    haptics.select();
    void sessions.pairNearby(mac).then((paired) => (paired ? haptics.success() : haptics.error()));
  };

  const [first, ...others] = macs;
  const wait = pairing.nearby ?? null;
  const body = (): ReactNode => {
    if (wait !== null) return <Waiting wait={wait} />;
    if (first === undefined) return <Looking permission={permission} />;
    return <Found mac={first} others={others} onPick={pick} />;
  };
  return (
    <View className="flex-1 bg-bg" style={{ paddingTop: insets.top, paddingBottom: Math.max(insets.bottom, 16) }}>
      {body()}
      {wait === null && pairing.error !== null ? (
        <>
          <Mono tone="alarmHigh" className="px-[22px] pt-4" accessibilityLiveRegion="assertive">
            {pairing.error}
          </Mono>
          {onWhy === undefined ? null : (
            <View className="px-[22px]">
              <Button label="Why?" variant="text" onPress={onWhy} />
            </View>
          )}
        </>
      ) : null}
      {wait === null ? (
        <View className="px-[22px] pt-2">
          <Button label="Scan a QR instead" variant="text" block onPress={onScan} />
        </View>
      ) : null}
    </View>
  );
}
