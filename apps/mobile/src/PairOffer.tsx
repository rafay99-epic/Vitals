import { sessions } from "@vitals/app/connection/session.ts";
import { useSession } from "@vitals/app/connection/useRemote.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { Modal, Pressable, StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { useMac } from "./lib/remote.ts";
import { BigButton, color, SheetCancel, SheetHeader, T } from "./ui/index.ts";

const hostOf = (baseUrl: string): string => {
  try {
    return new URL(baseUrl).host;
  } catch {
    return "a Mac on this Wi-Fi";
  }
};

function Replaces() {
  const mac = useMac();
  return <SheetHeader title="Pair with a different Mac?" detail={`This phone stops using ${mac?.name ?? "your Mac"}. Only go on if you just scanned a code on your own Mac.`} />;
}

/**
 * Asks before a pairing link from outside the app (the system camera, a web page) pairs this phone.
 * Over the pairing screens and the paired app alike, so it's a modal rather than a sheet.
 */
export function PairOffer() {
  const offer = useStore(sessions.offer);
  const pairing = useStore(sessions.pairing);
  const session = useSession();
  const insets = useSafeAreaInsets();
  if (offer === null) return null;
  return (
    <Modal transparent animationType="fade" statusBarTranslucent navigationBarTranslucent onRequestClose={() => sessions.declineOffer()}>
      <Pressable style={styles.scrim} onPress={() => sessions.declineOffer()} accessibilityLabel="Cancel" />
      <View style={[styles.panel, { paddingBottom: insets.bottom + 16 }]}>
        {session.status === "paired" ? <Replaces /> : <SheetHeader title="Pair with this Mac?" detail={`The link points to ${hostOf(offer.baseUrl)}.`} />}
        {pairing.error === null ? null : (
          <T v="small" color={color.red} style={styles.error}>
            {pairing.error}
          </T>
        )}
        <BigButton label={pairing.busy ? "Pairing" : pairing.error === null ? "Pair" : "Try again"} disabled={pairing.busy} onPress={() => void sessions.acceptOffer()} />
        <SheetCancel onPress={() => sessions.declineOffer()} />
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  scrim: { ...StyleSheet.absoluteFill, backgroundColor: color.scrim },
  error: { paddingHorizontal: 20, paddingBottom: 12 },
  panel: { position: "absolute", left: 0, right: 0, bottom: 0, backgroundColor: color.s2, borderTopLeftRadius: 28, borderTopRightRadius: 28, paddingTop: 22 },
});
