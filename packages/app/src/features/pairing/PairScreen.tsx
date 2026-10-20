import { normalizeCode, parsePairingUrl } from "@vitals/client-runtime";
import { PAIRING_CODE_LENGTH } from "@vitals/contracts";
import { Banner, Screen, Section, TextButton } from "@vitals/ui";
import { useState } from "react";
import { Platform, Text, TextInput, View } from "react-native";

import { sessions } from "../../connection/session.ts";
import { success } from "../../lib/haptics";
import { useStore } from "../../state/useStore.ts";
import { QrScanner } from "./QrScanner";

const initialBaseUrl = Platform.OS === "web" && typeof globalThis.location !== "undefined" ? globalThis.location.origin : "https://";

export function PairScreen() {
  const pairing = useStore(sessions.pairing);
  const [baseUrl, setBaseUrl] = useState(initialBaseUrl);
  const [code, setCode] = useState("");
  const [localError, setLocalError] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);
  const error = localError ?? pairing.error;

  const submit = (raw: string) => {
    const link = parsePairingUrl(raw);
    if (link === null) {
      setLocalError("That is not a Vitals pairing code. Check the Mac address and the 12 character code.");
      return;
    }
    setLocalError(null);
    setScanning(false);
    void sessions.pairWith(link).then((paired) => {
      if (paired) success();
    });
  };

  return (
    <Screen>
      <Text className="mt-10 text-3xl font-semibold text-ink">Pair with your Mac</Text>
      <Text className="mt-2 text-[15px] text-dim">
        In Vitals on the Mac, open Remote, then Pair new device. Scan the code or type it here. Both devices need Tailscale on.
      </Text>
      {error === null ? null : <Banner text={error} tone="bad" />}
      {Platform.OS === "web" ? null : (
        <Section title="Scan">
          {scanning ? (
            <QrScanner onCode={submit} />
          ) : (
            <TextButton label="Scan pairing QR" onPress={() => setScanning(true)} disabled={pairing.busy} />
          )}
        </Section>
      )}
      <Section title="Or enter it">
        <Text className="mb-1 text-xs text-mute">Mac address</Text>
        <TextInput
          value={baseUrl}
          onChangeText={setBaseUrl}
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="url"
          placeholder="https://your-mac.tailnet.ts.net:7445"
          placeholderTextColor="#6b6b6b"
          className="min-h-11 border border-line px-3 font-mono text-[15px] text-ink"
        />
        <Text className="mb-1 mt-4 text-xs text-mute">Pairing code</Text>
        <TextInput
          value={code}
          onChangeText={(value) => setCode(normalizeCode(value))}
          autoCapitalize="characters"
          autoCorrect={false}
          maxLength={PAIRING_CODE_LENGTH + 2}
          placeholder="ABCD EFGH JKLM"
          placeholderTextColor="#6b6b6b"
          className="min-h-11 border border-line px-3 font-mono text-lg tracking-widest text-ink"
        />
        <View className="mt-4">
          <TextButton
            label={pairing.busy ? "Pairing" : "Pair"}
            onPress={() => submit(`${baseUrl.replace(/\/$/, "")}/pair#code=${normalizeCode(code)}`)}
            disabled={pairing.busy || code.length !== PAIRING_CODE_LENGTH}
          />
        </View>
      </Section>
    </Screen>
  );
}
