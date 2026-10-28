/** The connection check's steps, verdict and report. Pure, so the wording is testable without a phone. */

export type StepId = "network" | "permission" | "found" | "answers" | "knows" | "tailscale";

export type Mark = "waiting" | "running" | "ok" | "warn" | "failed" | "skipped";

/** Why a step failed, which picks the fix. */
export type Cause =
  | "cellular"
  | "offline"
  | "denied"
  | "nothing-nearby"
  | "other-build"
  | "new-key"
  | "no-answer"
  | "not-vitals"
  | "unknown-phone"
  | "handshake"
  | "tailscale-login"
  | "tailscale-down";

export interface Step {
  readonly id: StepId;
  readonly mark: Mark;
  readonly detail: string | null;
  readonly cause: Cause | null;
}

export interface Fix {
  readonly title: string;
  readonly detail: string;
  /** What the fix's button does, when it has one. */
  readonly action: "settings" | "pair" | null;
}

export interface CheckRun {
  readonly steps: ReadonlyArray<Step>;
  readonly vpn: boolean;
  readonly startedAt: number;
  readonly finishedAt: number | null;
}

/** Wi-Fi steps run in this order and stop at the first failure; Tailscale runs on its own. */
export const WIFI_STEPS: ReadonlyArray<StepId> = ["network", "permission", "found", "answers", "knows"];

export const LABELS: Record<StepId, string> = {
  network: "On Wi-Fi",
  permission: "Allowed on the local network",
  found: "Found the Mac",
  answers: "The Mac answers",
  knows: "The Mac knows this phone",
  tailscale: "Tailscale",
};

export const freshRun = (now: number): CheckRun => ({
  steps: [...WIFI_STEPS, "tailscale" as const].map((id) => ({ id, mark: "waiting", detail: null, cause: null })),
  vpn: false,
  startedAt: now,
  finishedAt: null,
});

export const withStep = (run: CheckRun, id: StepId, mark: Mark, detail: string | null = null, cause: Cause | null = null): CheckRun => ({
  ...run,
  steps: run.steps.map((step) => (step.id === id ? { id, mark, detail, cause } : step)),
});

const FIXES: Record<Cause, (vpn: boolean) => Fix> = {
  cellular: () => ({ title: "Join the Mac's Wi-Fi.", detail: "On cellular the Mac is only reachable through Tailscale.", action: null }),
  offline: () => ({ title: "This phone is offline.", detail: "Turn on Wi-Fi or mobile data.", action: null }),
  denied: () => ({ title: "Allow Local network for Vitals.", detail: "Without it Android blocks every connection to the Mac.", action: "settings" }),
  "nothing-nearby": () => ({
    title: "No Vitals Mac on this Wi-Fi.",
    detail: "Open Vitals on the Mac and turn on Remote. Guest networks keep devices apart; use the main one.",
    action: null,
  }),
  "other-build": () => ({ title: "That Mac runs another Vitals build.", detail: "Dev apps pair with Vitals Dev; the others with Vitals and Vitals Nightly.", action: null }),
  "new-key": () => ({ title: "The Mac has a new key.", detail: "It was reset or reinstalled, or it's another Mac. Pair again.", action: "pair" }),
  "no-answer": (vpn) =>
    vpn
      ? { title: "A VPN is sending the traffic away.", detail: "Turn the VPN off, or let it reach the local network, then check again.", action: null }
      : {
          title: "The Mac is on this Wi-Fi but doesn't answer.",
          detail: "On the Mac, allow vitals-gateway in System Settings › Network › Firewall, or turn Remote off and on. Routers with client isolation keep devices apart.",
          action: null,
        },
  "not-vitals": () => ({ title: "Something else answers at that address.", detail: "Turn Remote off and on, on the Mac, so it announces its new address.", action: null }),
  "unknown-phone": () => ({ title: "The Mac doesn't know this phone.", detail: "It was removed on the Mac. Pair again.", action: "pair" }),
  handshake: () => ({ title: "The Mac hung up during the handshake.", detail: "Turn Remote off and on, on the Mac, then check again.", action: null }),
  "tailscale-login": () => ({ title: "Sign in to built-in Tailscale.", detail: "Away from the Mac's Wi-Fi, that's the only way in.", action: null }),
  "tailscale-down": () => ({ title: "Tailscale doesn't reach the Mac either.", detail: "Check that Tailscale is on, on the Mac.", action: null }),
};

const failed = (run: CheckRun, id: StepId): Step | undefined => run.steps.find((step) => step.id === id && step.mark === "failed");

/** The one thing to do next, or null when nothing failed. On cellular, a broken Tailscale is the real problem. */
export const fixFor = (run: CheckRun): Fix | null => {
  const wifi = run.steps.find((step) => WIFI_STEPS.includes(step.id) && step.mark === "failed");
  const tailscale = failed(run, "tailscale");
  const cause = wifi?.cause === "cellular" && tailscale?.cause ? tailscale.cause : (wifi?.cause ?? tailscale?.cause ?? null);
  return cause === null ? null : FIXES[cause](run.vpn);
};

const MARK_TEXT: Record<Mark, string> = { waiting: "..", running: "..", ok: "ok", warn: "!!", failed: "XX", skipped: "--" };

const clock = (at: number): string => new Date(at).toISOString().replace("T", " ").slice(0, 19);

/** Plain text to share: the build, every step, the fix, then the journal oldest first. */
export const reportOf = (run: CheckRun, build: string, journal: ReadonlyArray<{ readonly at: number; readonly kind: string; readonly text: string }>): string => {
  const fix = fixFor(run);
  return [
    `Vitals Remote ${build}, checked ${clock(run.startedAt)} UTC`,
    ...run.steps.map((step) => `${MARK_TEXT[step.mark]} ${LABELS[step.id]}${step.detail === null ? "" : `: ${step.detail}`}`),
    ...(fix === null ? [] : ["", `Fix: ${fix.title} ${fix.detail}`]),
    "",
    "Journal",
    ...journal.map((entry) => `${clock(entry.at)} ${entry.kind} ${entry.text}`),
  ].join("\n");
};
