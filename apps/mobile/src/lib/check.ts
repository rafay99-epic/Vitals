import { macKeyOf, nearby, startNearby } from "@vitals/app/connection/nearby.ts";
import { sessions } from "@vitals/app/connection/session.ts";
import { tunnel } from "@vitals/app/connection/tunnel.ts";
import { channel } from "@vitals/app/lib/variant.ts";
import { loadDeviceKey } from "@vitals/app/persistence/deviceKey.ts";
import { note } from "@vitals/app/state/journal.ts";
import { CLIENT_VERSION } from "@vitals/app/state/remote.ts";
import { knockOverLan, macKeyBytes, probeLan, Store } from "@vitals/client-runtime";
import { type FoundMac, requestLocalNetwork } from "@vitals/discovery";
import * as Network from "expo-network";

import { type Cause, type CheckRun, fixFor, freshRun, LABELS, type Mark, type StepId, WIFI_STEPS, withStep } from "./checkModel.ts";

/** The latest connection check, null until one runs. */
export const connectionCheck = new Store<CheckRun | null>(null);

const SEARCH_MS = 4_000;

const raw = (url: string) => {
  const socket = new WebSocket(url);
  socket.binaryType = "arraybuffer";
  return socket;
};

const sameBuild = (mac: FoundMac): boolean => (mac.txt["c"] === "dev") === (channel === "dev");
const nameOf = (mac: FoundMac): string => mac.txt["n"] ?? mac.name;

/** Waits until Bonjour shows a Mac that `wanted` accepts, or the time runs out, and returns what it saw. */
const lookNearby = (wanted: (mac: FoundMac) => boolean): Promise<ReadonlyArray<FoundMac>> =>
  new Promise((resolve) => {
    startNearby();
    if (nearby.get().some(wanted)) return resolve(nearby.get());
    const stop = nearby.subscribe(() => {
      if (!nearby.get().some(wanted)) return;
      clearTimeout(timer);
      stop();
      resolve(nearby.get());
    });
    const timer = setTimeout(() => {
      stop();
      resolve(nearby.get());
    }, SEARCH_MS);
  });

let running: Promise<void> | null = null;

/** Runs the check once; a second call while one runs joins it. */
export const runCheck = (): Promise<void> => {
  running ??= check().finally(() => {
    running = null;
  });
  return running;
};

const check = async (): Promise<void> => {
  let run = freshRun(Date.now());
  const set = (id: StepId, mark: Mark, detail: string | null = null, cause: Cause | null = null) => {
    run = withStep(run, id, mark, detail, cause);
    connectionCheck.set(run);
  };
  const stopWifi = (from: StepId) => {
    for (const id of WIFI_STEPS.slice(WIFI_STEPS.indexOf(from))) set(id, "skipped");
  };
  connectionCheck.set(run);
  const session = sessions.session.get();
  const credentials = session.status === "paired" ? session.remote.link.get() : null;

  // Tailscale doesn't depend on Wi-Fi, so it runs alongside.
  const away = checkTailscale(credentials?.baseUrl ?? null, credentials?.builtInTailscale === true ? (credentials.macKey ?? null) : undefined, set);

  wifi: {
    set("network", "running");
    const network = await Network.getNetworkStateAsync().catch(() => null);
    const type = network?.type;
    if (network?.isConnected === false || type === Network.NetworkStateType.NONE) {
      set("network", "failed", "Offline", "offline");
      stopWifi("permission");
      break wifi;
    }
    if (type === Network.NetworkStateType.CELLULAR) {
      set("network", "failed", "On cellular", "cellular");
      stopWifi("permission");
      break wifi;
    }
    if (type === Network.NetworkStateType.VPN) {
      run = { ...run, vpn: true };
      set("network", "warn", "A VPN is on and can send traffic away from the Mac");
    } else set("network", "ok", type === Network.NetworkStateType.ETHERNET ? "Ethernet" : null);

    set("permission", "running");
    if ((await requestLocalNetwork()) === "denied") {
      set("permission", "failed", "Android blocks this app from the local network", "denied");
      stopWifi("found");
      break wifi;
    }
    set("permission", "ok");

    set("found", "running");
    const key = credentials?.macKey ?? null;
    const seen = await lookNearby((mac) => sameBuild(mac) && (key === null || macKeyOf(mac) === key));
    const ours = seen.filter(sameBuild);
    const match = key === null ? ours.find((mac) => macKeyOf(mac) !== null) : ours.find((mac) => macKeyOf(mac) === key);
    const saved = credentials?.lan?.[0] ?? null;
    let target: { readonly host: string; readonly port: number; readonly key: string | null } | null = null;
    if (match !== undefined) {
      target = { host: match.host, port: match.port, key: macKeyOf(match) };
      set("found", "ok", `${nameOf(match)} · ${match.host}:${String(match.port)}${key === null ? "" : " · key matches"}`);
    } else if (ours.length > 0 && key !== null) {
      set("found", "failed", `Found ${ours.map(nameOf).join(", ")}, not with this phone's Mac key`, "new-key");
    } else if (saved !== null) {
      // Some routers drop Bonjour; the address saved at pairing may still answer.
      target = { host: saved.host, port: saved.port, key };
      set("found", "warn", `Not seen on this Wi-Fi; trying the saved address ${saved.host}:${String(saved.port)}`);
    } else if (seen.length > 0) {
      set("found", "failed", `Found ${seen.map(nameOf).join(", ")}, a different Vitals build`, "other-build");
    } else {
      set("found", "failed", `Nothing in ${String(SEARCH_MS / 1000)} s`, "nothing-nearby");
    }
    if (target === null) {
      stopWifi("answers");
      break wifi;
    }

    set("answers", "running");
    const started = Date.now();
    const probe = await probeLan(target.host, target.port, target.key, fetch, 3_000);
    if (!probe.ok) {
      const cause: Cause = probe.why.includes("different key") ? "new-key" : probe.why.startsWith("answered") ? "not-vitals" : "no-answer";
      set("answers", "failed", probe.why.charAt(0).toUpperCase() + probe.why.slice(1), cause);
      stopWifi("knows");
      break wifi;
    }
    set("answers", "ok", `In ${String(Date.now() - started)} ms`);

    if (credentials === null) {
      set("knows", "skipped", "Not paired yet");
      break wifi;
    }
    set("knows", "running");
    const device = await loadDeviceKey().catch(() => null);
    if (key === null || device === null) {
      set("knows", "skipped", "Paired without a Wi-Fi key");
      break wifi;
    }
    const knock = await knockOverLan({ host: target.host, port: target.port, macKey: macKeyBytes(key), device, client: CLIENT_VERSION, raw });
    if (knock.ok) set("knows", "ok");
    else set("knows", "failed", knock.why, knock.unknown ? "unknown-phone" : "handshake");
  }

  await away;
  // Checking is also asking: a paired link in backoff tries again now instead of at its next retry.
  if (session.status === "paired") session.remote.connection.wake("manual");
  run = { ...run, finishedAt: Date.now() };
  connectionCheck.set(run);
  const fix = fixFor(run);
  note(
    "check",
    `${run.steps.map((step) => `${LABELS[step.id]}: ${step.mark}${step.detail === null ? "" : ` (${step.detail})`}`).join("; ")}${fix === null ? "" : `. Fix: ${fix.title}`}`,
  );
};

/** `builtIn` is the Mac key when this phone runs Tailscale itself, undefined when the system Tailscale app carries the route. */
const checkTailscale = async (baseUrl: string | null, builtIn: string | null | undefined, set: (id: StepId, mark: Mark, detail?: string | null, cause?: Cause | null) => void) => {
  if (baseUrl === null) return set("tailscale", "skipped", "Not set up");
  set("tailscale", "running");
  const started = Date.now();
  const answeredIn = () => `The Mac answered in ${String(Date.now() - started)} ms`;
  if (builtIn !== undefined) {
    const state = tunnel.get();
    if (state._tag === "NeedsLogin") return set("tailscale", "failed", "Needs a sign-in", "tailscale-login");
    if (state._tag === "Failed") return set("tailscale", "failed", state.reason, "tailscale-down");
    if (state._tag !== "Ready") return set("tailscale", "failed", "Not running", "tailscale-down");
    // The built-in tunnel forwards the Wi-Fi protocol from a local port.
    const probe = await probeLan("127.0.0.1", state.port, builtIn, fetch, 5_000);
    return probe.ok ? set("tailscale", "ok", answeredIn()) : set("tailscale", "failed", probe.why, "tailscale-down");
  }
  const answered = await fetch(`${baseUrl.replace(/\/$/, "")}/api/health`, { signal: AbortSignal.timeout(5_000) }).then(
    (response) => response.ok,
    () => false,
  );
  if (answered) set("tailscale", "ok", answeredIn());
  else set("tailscale", "failed", "No answer in 5 s", "tailscale-down");
};
