import { isPending, type Pending, secondsLeft } from "@vitals/app/components/PendingOrder.tsx";
import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { orderLabel } from "@vitals/app/state/commands.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import { useNow } from "@vitals/app/state/useVitals.ts";
import { StyleSheet } from "react-native";
import Animated, { FadeOut, SlideInDown } from "react-native-reanimated";

import { useAccess } from "./lib/remote.ts";
import { color, curve, motion, T, Tap, toast } from "./ui/index.ts";

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
  return (
    <Animated.View entering={SlideInDown.duration(motion.toastIn).easing(curve.out)} exiting={FadeOut.duration(motion.toastOut)} accessibilityRole="alert" style={styles.strip}>
      <T v="strong" color={color.bg} style={styles.text}>{`${VERB[receipt.kind] ?? orderLabel(receipt.kind)} in ${secondsLeft(receipt.deadlineAt, now)}`}</T>
      {access.operate ? (
        <Tap onPress={() => void remote.cancel(receipt).then((ok) => ok && toast.show("Cancelled"))} accessibilityRole="button" hitSlop={12}>
          <T v="strong" color={color.bg} style={styles.cancel}>
            Cancel
          </T>
        </Tap>
      ) : null}
    </Animated.View>
  );
}

/** Pinned above the dock while timed orders (shut down, restart) count down on the Mac, one strip each. */
export function PendingStrip() {
  const pending = useStore(useRemote().events.receipts).filter(isPending);
  return pending.map((receipt) => <Countdown key={receipt.id} receipt={receipt} />);
}

const styles = StyleSheet.create({
  strip: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 12, backgroundColor: color.orange, borderRadius: 16, paddingHorizontal: 14, paddingVertical: 12 },
  text: { flex: 1 },
  cancel: { textDecorationLine: "underline" },
});
