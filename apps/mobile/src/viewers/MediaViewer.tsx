import { useEvent } from "expo";
import { useVideoPlayer, VideoView } from "expo-video";
import { StyleSheet, View } from "react-native";

import { Bar, BigButton, color, Icon, T } from "../ui/index.ts";

/** "1:05", from seconds. */
const clock = (seconds: number): string => {
  const whole = Math.max(0, Math.floor(seconds));
  return `${String(Math.floor(whole / 60))}:${String(whole % 60).padStart(2, "0")}`;
};

/** A sound: nothing to watch, so play/pause and where it is, updated once a second. */
function Sound({ uri }: { readonly uri: string }) {
  const player = useVideoPlayer(uri, (created) => {
    created.timeUpdateEventInterval = 1;
    created.play();
  });
  const { isPlaying } = useEvent(player, "playingChange", { isPlaying: player.playing });
  const { currentTime } = useEvent(player, "timeUpdate", { currentTime: 0, currentLiveTimestamp: null, currentOffsetFromLive: null, bufferedPosition: 0 });
  const duration = player.duration;
  return (
    <View style={styles.sound}>
      <View style={styles.tile}>
        <Icon name="sound" size={34} color={color.blue} />
      </View>
      <View style={styles.bar}>
        <Bar value={duration > 0 ? currentTime / duration : 0} />
      </View>
      <T v="mono">{duration > 0 ? `${clock(currentTime)} of ${clock(duration)}` : clock(currentTime)}</T>
      <View style={styles.button}>
        <BigButton
          label={isPlaying ? "Pause" : "Play"}
          onPress={() => {
            if (isPlaying) player.pause();
            else if (duration > 0 && currentTime >= duration - 0.5) player.replay();
            else player.play();
          }}
        />
      </View>
    </View>
  );
}

/** A video with the system's own controls, or a sound with play/pause, playing from the cached copy. */
export function MediaViewer({ uri, sound }: { readonly uri: string; readonly sound: boolean }) {
  return sound ? <Sound uri={uri} /> : <Movie uri={uri} />;
}

function Movie({ uri }: { readonly uri: string }) {
  const player = useVideoPlayer(uri, (created) => {
    created.play();
  });
  return <VideoView player={player} nativeControls contentFit="contain" style={styles.fill} />;
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: color.bg },
  sound: { flex: 1, alignItems: "center", justifyContent: "center", gap: 10, paddingHorizontal: 24 },
  tile: { width: 84, height: 84, borderRadius: 22, backgroundColor: color.s3, alignItems: "center", justifyContent: "center" },
  bar: { alignSelf: "stretch", marginTop: 6 },
  button: { alignSelf: "stretch", marginTop: 14 },
});
