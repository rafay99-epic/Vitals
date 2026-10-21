import Constants from "expo-constants";

const variant: unknown = Constants.expoConfig?.extra?.["variant"];

export const isDevBuild = variant !== "prod";
