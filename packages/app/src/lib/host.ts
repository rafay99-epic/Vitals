import type { Credentials } from "../persistence/credentialsSchema.ts";

export const hostOf = (baseUrl: string): string => baseUrl.replace(/^https?:\/\//, "");

export const addressOf = (credentials: Credentials): string => {
  if (credentials.baseUrl !== null) return hostOf(credentials.baseUrl);
  const lan = credentials.lan?.[0];
  return lan === undefined ? "on your Wi-Fi" : lan.host;
};
