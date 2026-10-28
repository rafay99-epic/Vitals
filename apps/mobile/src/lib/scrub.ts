import type { ReactNativeOptions } from "@sentry/react-native";
import { scrubRecord, scrubText } from "@vitals/shared";

type Log = Parameters<NonNullable<ReactNativeOptions["beforeSendLog"]>>[0];

export const scrubLog = (log: Log): Log => ({
  ...log,
  message: scrubText(String(log.message)),
  ...(log.attributes === undefined ? {} : { attributes: scrubRecord(log.attributes) }),
});
