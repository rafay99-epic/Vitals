import { useRemote } from "@vitals/app/connection/useRemote.ts";
import { isLink } from "@vitals/app/features/clips/format.ts";
import { useStore } from "@vitals/app/state/useStore.ts";
import * as Clipboard from "expo-clipboard";
import { StyleSheet, View } from "react-native";
import Animated, { FadeOut, SlideInDown } from "react-native-reanimated";

import { phoneCopy, sendPastedImage, sendText } from "./lib/phoneCopies.ts";
import { color, curve, Icon, motion, T, Tap } from "./ui/index.ts";

const DONE = "On your Mac's clipboard. Paste with ⌘V.";

const preview = (text: string): string => text.replace(/^https?:\/\//, "").replace(/\s+/g, " ");

export function CopyStrip() {
  const remote = useRemote();
  const copy = useStore(phoneCopy);
  if (copy === null || (copy._tag === "Unread" && !Clipboard.isPasteButtonAvailable)) return null;
  const title = copy._tag === "Unread" ? "You copied something" : isLink(copy.text) ? "You copied a link" : "You copied text";
  const detail = copy._tag === "Unread" ? "Paste it to send it to your Mac" : preview(copy.text);
  return (
    <Animated.View entering={SlideInDown.duration(motion.toastIn).easing(curve.out)} exiting={FadeOut.duration(motion.toastOut)} style={styles.strip}>
      <Icon name="clipboard" size={16} color={color.ink2} />
      <View style={styles.text}>
        <T v="medium">{title}</T>
        <T v="mono" numberOfLines={1}>
          {detail}
        </T>
      </View>
      {copy._tag === "Unread" ? (
        <Clipboard.ClipboardPasteButton
          style={styles.paste}
          backgroundColor={color.s2}
          foregroundColor={color.ink}
          cornerStyle="medium"
          displayMode="iconAndLabel"
          acceptedContentTypes={["plain-text", "url", "image"]}
          imageOptions={{ format: "png" }}
          onPress={(data) => void (data.type === "text" ? sendText(remote, data.text, DONE) : sendPastedImage(remote, data.data, DONE))}
        />
      ) : (
        <Tap onPress={() => void sendText(remote, copy.text, DONE)} accessibilityRole="button" style={styles.send}>
          <T v="strong" color={color.bg}>
            Send to Mac
          </T>
        </Tap>
      )}
      <Tap onPress={() => phoneCopy.set(null)} accessibilityRole="button" accessibilityLabel="Dismiss" hitSlop={10}>
        <Icon name="close" size={14} color={color.dim} />
      </Tap>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  strip: { flexDirection: "row", alignItems: "center", gap: 10, backgroundColor: color.s3, borderWidth: 1, borderColor: color.line2, borderRadius: 16, paddingHorizontal: 12, paddingVertical: 10 },
  text: { flex: 1, gap: 1 },
  send: { backgroundColor: color.yellow, borderRadius: 10, paddingHorizontal: 11, paddingVertical: 7 },
  paste: { width: 96, height: 34 },
});
