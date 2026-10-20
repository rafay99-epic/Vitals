import { fontAssets } from "@vitals/ui";
import { useFonts } from "expo-font";

export const useAppFonts = (): boolean => {
  const [loaded, error] = useFonts(fontAssets);
  return loaded || error !== null;
};
