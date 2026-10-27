export const RETRY_BASE_DELAY_MS = 1_000;
// The loop only backs off while the app is open (a suspended connection waits for a wake instead),
// so the cap stays short enough that a Mac waking from sleep is found within half a minute.
export const RETRY_MAX_DELAY_MS = 30_000;
export const BACKOFF_RESET_AFTER_MS = 30_000;

export const retryDelayMs = (failureCount: number, random: number): number => {
  const ceiling = Math.min(RETRY_MAX_DELAY_MS, RETRY_BASE_DELAY_MS * 2 ** (failureCount + 1));
  return Math.round(ceiling / 2 + (ceiling / 2) * random);
};
