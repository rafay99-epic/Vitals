import type { CommandReceipt } from "@vitals/contracts";

/** Timed orders (shut down, restart, log out) counting down on the Mac. */
export type Pending = CommandReceipt & { readonly deadlineAt: number };

export const isPending = (receipt: CommandReceipt): receipt is Pending => receipt.status === "pending" && receipt.deadlineAt !== null;

export const secondsLeft = (until: number, now: number): string => `${String(Math.max(0, Math.ceil((until - now) / 1000)))} s`;

/**
 * A countdown well past its deadline is over, even if its last receipt never arrived (the Mac shut
 * down before the gateway could record it). Stop showing it rather than "0 s" forever.
 */
export const isOverdue = (receipt: Pending, now: number): boolean => now - receipt.deadlineAt > 10_000;
