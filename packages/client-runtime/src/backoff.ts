export const RETRY_BASE_DELAY_MS = 1_000;
// On screen the cap stays short enough that a Mac waking from sleep is found within half a minute.
export const RETRY_MAX_DELAY_MS = 30_000;
// A link kept alive with the app closed waits longer between tries: each one wakes the radio. A network change still tries at once.
export const BACKGROUND_RETRY_MAX_DELAY_MS = 5 * 60_000;
export const BACKOFF_RESET_AFTER_MS = 30_000;

export const retryDelayMs = (failureCount: number, random: number, cap = RETRY_MAX_DELAY_MS): number => {
  const ceiling = Math.min(cap, RETRY_BASE_DELAY_MS * 2 ** (failureCount + 1));
  return Math.round(ceiling / 2 + (ceiling / 2) * random);
};
