import { normalizeCode, parsePairingDeepLink, parsePairingUrl, type PairingLink } from "@vitals/client-runtime";
import { PAIRING_CODE_LENGTH } from "@vitals/contracts";
import { Button, CodeInput, Field, Mark, Mono, Row, Screen, Section, Serif } from "@vitals/ui";
import { useRef, useState } from "react";
import { Platform, View } from "react-native";

import { sessions } from "../../connection/session.ts";
import { haptics } from "../../lib/haptics";
import { useStore } from "../../state/useStore.ts";
import { QrScanner } from "./QrScanner";

const WEB = Platform.OS === "web";
const initialBaseUrl = WEB && typeof globalThis.location !== "undefined" ? globalThis.location.origin : "https://";

const SAVED_IN = WEB ? "a secure cookie" : "the keychain";

const linkFrom = (raw: string): PairingLink | null => parsePairingUrl(raw) ?? parsePairingDeepLink(raw);

function Viewfinder({ onCode }: { readonly onCode: (value: string) => void }) {
  const last = useRef<string | null>(null);
  const scanned = (value: string) => {
    if (value === last.current) return;
    last.current = value;
    onCode(value);
  };
  return (
    <View className="gap-3 px-[22px] pb-2">
      <View className="aspect-square overflow-hidden bg-raise">
        <QrScanner onCode={scanned} />
        <View className="absolute left-4 top-4 h-8 w-8 border-l-2 border-t-2 border-pulse" pointerEvents="none" />
        <View className="absolute right-4 top-4 h-8 w-8 border-r-2 border-t-2 border-pulse" pointerEvents="none" />
        <View className="absolute bottom-4 left-4 h-8 w-8 border-b-2 border-l-2 border-pulse" pointerEvents="none" />
        <View className="absolute bottom-4 right-4 h-8 w-8 border-b-2 border-r-2 border-pulse" pointerEvents="none" />
      </View>
      <Mono className="text-center">Point the camera at the code on your Mac</Mono>
    </View>
  );
}

function Progress() {
  return (
    <Section title="Pairing">
      <Row plain label="Checking the code with your Mac" detail={`The session is kept in ${SAVED_IN}.`} value="now" valueTone="pulse" />
    </Section>
  );
}

export function PairScreen({ onFind }: { readonly onFind?: (() => void) | undefined }) {
  const pairing = useStore(sessions.pairing);
  const [baseUrl, setBaseUrl] = useState(initialBaseUrl);
  const [code, setCode] = useState("");
  const [localError, setLocalError] = useState<string | null>(null);
  const error = localError ?? pairing.error;

  const start = (link: PairingLink | null) => {
    if (pairing.busy) return;
    if (link === null) {
      haptics.error();
      setLocalError("That is not a Vitals pairing code. Check the Mac address and the 12 letter code.");
      return;
    }
    setLocalError(null);
    void sessions.handleLink(link).then((paired) => (paired ? haptics.success() : haptics.error()));
  };

  const submit = () => start(parsePairingUrl(`${baseUrl.trim().replace(/\/$/, "")}/pair#code=${code}`));

  return (
    <Screen>
      <View className="gap-3 px-[22px] pb-4 pt-8">
        <Mark width={42} />
        <Serif size="l" accessibilityRole="header">
          Pair with your Mac
        </Serif>
        <Mono>In Vitals on the Mac, open Remote, then Pair new device.</Mono>
      </View>
      {WEB ? null : (
        <Section title="Scan">
          <Viewfinder onCode={(value) => start(linkFrom(value))} />
        </Section>
      )}
      <Section title="Or enter it">
        {WEB ? null : (
          <Field
            label="Mac address"
            mono
            value={baseUrl}
            onChangeText={setBaseUrl}
            autoCapitalize="none"
            autoCorrect={false}
            keyboardType="url"
            placeholder="https://your-mac.tailnet.ts.net"
            hint="The address shown under the code on your Mac"
          />
        )}
        <CodeInput value={code} length={PAIRING_CODE_LENGTH} onChange={(value) => setCode(normalizeCode(value))} onSubmit={submit} error={error} />
        <View className="px-[22px] pb-5 pt-2">
          <Button label={pairing.busy ? "Pairing" : "Pair"} block disabled={pairing.busy || code.length !== PAIRING_CODE_LENGTH} onPress={submit} />
        </View>
      </Section>
      {pairing.busy ? <Progress /> : null}
      {onFind === undefined ? null : (
        <View className="px-[22px] pt-4">
          <Button label="Find my Mac on this Wi-Fi" variant="text" block onPress={onFind} />
        </View>
      )}
      <Mono className="px-[22px] pt-6">Pairing stays between your devices. Nothing goes through our servers.</Mono>
    </Screen>
  );
}
