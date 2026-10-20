import type { Channel } from "@vitals/ui";

export type ChartStackParams = {
  Chart: undefined;
  Channel: { readonly channel: Channel };
};

export type RecordStackParams = {
  Record: undefined;
  Diagnostics: undefined;
};

export type TabParams = {
  ChartTab: undefined;
  Orders: undefined;
  Ward: undefined;
  Alarms: undefined;
  RecordTab: undefined;
};
