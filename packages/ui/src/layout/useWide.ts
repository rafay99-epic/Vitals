import { useWindowDimensions } from "react-native";

import { WIDE_MIN_WIDTH } from "../theme.ts";

export const useWide = (): boolean => useWindowDimensions().width >= WIDE_MIN_WIDTH;
