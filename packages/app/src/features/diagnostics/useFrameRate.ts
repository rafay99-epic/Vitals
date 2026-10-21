import { useFocusEffect } from "@react-navigation/native";
import { useCallback } from "react";

import { diagnostics } from "../../state/diagnostics.ts";

const WINDOW_MS = 1000;

export const useFrameRate = (): void => {
  useFocusEffect(
    useCallback(() => {
      if (!diagnostics.enabled) return;
      let frames = 0;
      let windowStart = performance.now();
      let handle = requestAnimationFrame(function count() {
        const now = performance.now();
        frames += 1;
        if (now - windowStart >= WINDOW_MS) {
          diagnostics.frame(Math.round((frames * WINDOW_MS) / (now - windowStart)));
          frames = 0;
          windowStart = now;
        }
        handle = requestAnimationFrame(count);
      });
      return () => cancelAnimationFrame(handle);
    }, []),
  );
};
