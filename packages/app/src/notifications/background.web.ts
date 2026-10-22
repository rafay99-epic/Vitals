import type { Alert } from "@vitals/contracts";

import { notifyAlert } from "./alerts";

const seen = new Set<string>();

/// The browser has no shade to keep in sync: notify each new alert once, and only while the tab is hidden.
export const syncAlerts = async (open: ReadonlyArray<Alert>, quiet: boolean): Promise<void> => {
  const fresh = open.filter((alert) => !seen.has(alert.id));
  for (const alert of fresh) seen.add(alert.id);
  if (!quiet) await Promise.all(fresh.map((alert) => notifyAlert(alert, false)));
};

export const startAlertWatch = async (): Promise<boolean> => false;

export const stopAlertWatch = async (): Promise<void> => {};
