export type MetricKind = "cpu" | "gpu" | "thermal" | "fans" | "memory" | "battery" | "power" | "network";

export type LiveStackParams = {
  Live: undefined;
  Metric: { kind: MetricKind };
};

export type TabParams = {
  LiveTab: undefined;
  Control: undefined;
  Processes: undefined;
  Guard: undefined;
  More: undefined;
};
