import { Geist_400Regular } from "@expo-google-fonts/geist/400Regular/index.js";
import { Geist_500Medium } from "@expo-google-fonts/geist/500Medium/index.js";
import { Geist_600SemiBold } from "@expo-google-fonts/geist/600SemiBold/index.js";
import { GeistMono_400Regular } from "@expo-google-fonts/geist-mono/400Regular/index.js";
import { GeistMono_500Medium } from "@expo-google-fonts/geist-mono/500Medium/index.js";
import { InstrumentSerif_400Regular } from "@expo-google-fonts/instrument-serif/400Regular/index.js";
import { InstrumentSerif_400Regular_Italic } from "@expo-google-fonts/instrument-serif/400Regular_Italic/index.js";

export const fontAssets = {
  "InstrumentSerif-Regular": InstrumentSerif_400Regular,
  "InstrumentSerif-Italic": InstrumentSerif_400Regular_Italic,
  "Geist-Regular": Geist_400Regular,
  "Geist-Medium": Geist_500Medium,
  "Geist-SemiBold": Geist_600SemiBold,
  "GeistMono-Regular": GeistMono_400Regular,
  "GeistMono-Medium": GeistMono_500Medium,
} as const;
