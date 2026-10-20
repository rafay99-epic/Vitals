import type { Alert } from "@vitals/contracts";

import { notifyAlert } from "./alerts";

export const rememberAlertSeq = async (_seq: number): Promise<void> => {};

export const notifyOnce = (alert: Alert): Promise<void> => notifyAlert(alert);

export const startAlertWatch = async (): Promise<boolean> => false;

export const stopAlertWatch = async (): Promise<void> => {};
