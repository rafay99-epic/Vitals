import {
  type ConnectionOptions,
  deviceKeyText,
  macKeyBytes,
  pair,
  pairOverLan,
  parsePairingDeepLink,
  parsePairingUrl,
  type PairingLink,
  Store,
  unpair,
} from "@vitals/client-runtime";
import type { FoundMac } from "@vitals/discovery";
import type { KeyPair } from "@vitals/noise";
import * as Network from "expo-network";
import { AppState, Linking, Platform } from "react-native";

import { deviceInfo } from "../lib/device.ts";
import { forgetCalmAction, onCalmAction, prepareNotifications } from "../notifications/alerts";
import { markAlertsSeen, notifyOnce, startAlertWatch, stopAlertWatch } from "../notifications/background";
import { clearCredentials, loadCredentials, saveCredentials } from "../persistence/credentials";
import { loadDeviceKey } from "../persistence/deviceKey";
import type { Credentials } from "../persistence/credentialsSchema.ts";
import { Remote } from "../state/remote.ts";
import { localNetwork, macKeyOf, startNearby, stopNearby } from "./nearby.ts";
import { runTunnelOnDemand } from "./tunnel.ts";

const SUSPEND_AFTER_MS = 10_000;

export type Session =
  | { readonly status: "loading" }
  | { readonly status: "unpaired" }
  | { readonly status: "paired"; readonly remote: Remote };

export interface NearbyWait {
  readonly name: string;
  readonly code: string | null;
  readonly expiresAt: number | null;
}

export interface PairingState {
  readonly busy: boolean;
  readonly error: string | null;
  readonly nearby?: NearbyWait | null;
}

const NEARBY_FAILURES = {
  denied: "The Mac said no. Try again and click Allow on the Mac.",
  expired: "The Mac did not answer in time. Try again and click Allow on the Mac.",
  busy: "The Mac has too many requests waiting. Try again in a minute.",
  incompatible: "Update Vitals on the Mac and on this phone, then try again.",
  unreachable: "Could not reach the Mac on this Wi-Fi. Check that Remote is on.",
  mismatch: "That Mac answered with a different key. Pair with the QR on the Mac instead.",
  cancelled: null,
} as const;

const openSocket: ConnectionOptions["webSocket"] = (url, options) => {
  const socket = new WebSocket(url, typeof options === "string" || Array.isArray(options) ? options : undefined);
  socket.binaryType = "arraybuffer";
  return socket;
};

const OFF_LOCAL: ReadonlySet<Network.NetworkStateType> = new Set([Network.NetworkStateType.CELLULAR, Network.NetworkStateType.NONE]);

const trackLocalNetwork = (state: Network.NetworkState) => localNetwork.set(state.type === undefined || !OFF_LOCAL.has(state.type));

const launchPairingLink = async (): Promise<PairingLink | null> => {
  if (Platform.OS === "web") return typeof globalThis.location === "undefined" ? null : parsePairingUrl(globalThis.location.href);
  const initial = await Linking.getInitialURL();
  return typeof initial === "string" ? parsePairingDeepLink(initial) : null;
};

class SessionManager {
  readonly session = new Store<Session>({ status: "loading" });
  readonly pairing = new Store<PairingState>({ busy: false, error: null });
  readonly welcome = new Store<boolean>(false);
  private teardown: (() => void) | null = null;
  private started = false;
  private queued: PairingLink | null = null;
  private readonly usedCodes = new Set<string>();
  private keys: Promise<KeyPair | null> | null = null;
  private cancelNearby: (() => void) | null = null;

  private deviceKey(): Promise<KeyPair | null> {
    this.keys ??= loadDeviceKey().catch(() => null);
    return this.keys;
  }

  receive(link: PairingLink | null): void {
    if (link === null) return;
    if (this.started) void this.handleLink(link);
    else this.queued = link;
  }

  async handleLink(link: PairingLink | null, quiet = false): Promise<boolean> {
    if (link === null || this.usedCodes.has(link.code)) return false;
    this.usedCodes.add(link.code);
    const paired = await this.pairWith(link, quiet);
    if (!paired) this.usedCodes.delete(link.code);
    return paired;
  }

  start(): void {
    if (this.started) return;
    this.started = true;
    void (async () => {
      const early = this.queued;
      this.queued = null;
      const credentials = await loadCredentials();
      // A paired app that restarts (an update, a reload) still sees the pairing link it was
      // opened with. If that stale link fails, keep the saved pairing instead of flashing the
      // pairing screen.
      if (await this.handleLink(early ?? (await launchPairingLink()), credentials !== null)) return;
      if (this.session.get().status === "paired") return;
      if (credentials === null) this.session.set({ status: "unpaired" });
      else this.open(credentials, await this.deviceKey());
    })().catch((error: unknown) => {
      this.pairing.set({ busy: false, error: error instanceof Error ? error.message : "Could not read this device's pairing. Pair again." });
      this.session.set({ status: "unpaired" });
    });
  }

  /** Pairs with a link. `quiet` failures leave the session alone, for a stale launch link. */
  async pairWith(link: PairingLink, quiet = false): Promise<boolean> {
    this.pairing.set({ busy: !quiet, error: null });
    try {
      return await this.completePairing(link, quiet);
    } catch {
      this.failPairing("Pairing could not be saved on this device. Try again.", quiet);
      return false;
    }
  }

  private failPairing(message: string, quiet: boolean): void {
    this.pairing.set({ busy: false, error: quiet ? null : message });
    if (!quiet && this.session.get().status === "loading") this.session.set({ status: "unpaired" });
  }

  private async completePairing(link: PairingLink, quiet: boolean): Promise<boolean> {
    const device = await this.deviceKey();
    const lanKey = device === null ? null : deviceKeyText(device);
    const outcome = await pair(link, deviceInfo(), undefined, lanKey);
    if (!outcome.ok) {
      this.failPairing(outcome.message, quiet);
      return false;
    }
    if (Platform.OS === "web") globalThis.history?.replaceState(null, "", "/");
    return this.adopt({
      baseUrl: link.baseUrl,
      token: outcome.response.token,
      deviceId: outcome.response.deviceId,
      scopes: outcome.response.scopes,
      pairedAt: Date.now(),
      macKey: link.macKey,
      lanBound: lanKey !== null,
    });
  }

  private async adopt(credentials: Credentials): Promise<boolean> {
    const previous = Platform.OS === "web" ? null : await loadCredentials().catch(() => null);
    try {
      await saveCredentials(credentials);
    } catch (error) {
      if (credentials.baseUrl !== null) void unpair(credentials.baseUrl, credentials.token);
      throw error;
    }
    if (previous !== null && previous.deviceId !== credentials.deviceId && previous.baseUrl !== null) void unpair(previous.baseUrl, previous.token);
    this.pairing.set({ busy: false, error: null, nearby: null });
    this.welcome.set(true);
    this.open(credentials, await this.deviceKey());
    return true;
  }

  async pairNearby(mac: FoundMac): Promise<boolean> {
    const key = macKeyOf(mac);
    const device = await this.deviceKey();
    if (key === null || device === null) {
      this.pairing.set({ busy: false, error: "This phone cannot keep a Wi-Fi key. Pair with the QR instead.", nearby: null });
      return false;
    }
    const name = mac.txt["n"] ?? mac.name;
    this.pairing.set({ busy: true, error: null, nearby: { name, code: null, expiresAt: null } });
    const attempt = pairOverLan({
      host: mac.host,
      port: mac.port,
      macKey: macKeyBytes(key),
      device,
      info: deviceInfo(),
      raw: openSocket,
      onWaiting: (code, expiresAt) => this.pairing.set({ busy: true, error: null, nearby: { name, code, expiresAt } }),
    });
    this.cancelNearby = attempt.cancel;
    const outcome = await attempt.outcome;
    this.cancelNearby = null;
    if (!outcome.ok) {
      this.pairing.set({ busy: false, error: NEARBY_FAILURES[outcome.reason], nearby: null });
      return false;
    }
    const found = { host: mac.host, port: mac.port };
    const lan = [found, ...outcome.result.routes.lan.filter((endpoint) => endpoint.host !== found.host || endpoint.port !== found.port)];
    try {
      return await this.adopt({
        baseUrl: outcome.result.routes.tailnet,
        token: outcome.result.token,
        deviceId: outcome.result.deviceId,
        scopes: outcome.result.scopes,
        pairedAt: Date.now(),
        macKey: outcome.result.routes.key,
        lan,
        owner: outcome.result.routes.owner ?? null,
        lanBound: true,
      });
    } catch {
      this.pairing.set({ busy: false, error: "Pairing could not be saved on this device. Try again.", nearby: null });
      return false;
    }
  }

  cancelPairNearby(): void {
    this.cancelNearby?.();
  }

  finishWelcome(): void {
    this.welcome.set(false);
  }

  async forget(): Promise<void> {
    const current = this.session.get();
    if (Platform.OS === "web") {
      if (current.status === "paired") current.remote.connection.suspend();
      if (!(await clearCredentials())) {
        if (current.status === "paired") {
          current.remote.connection.wake("manual");
          current.remote.show("Could not reach your Mac to unpair. Try again.", "bad");
        }
        return;
      }
      this.close();
      this.session.set({ status: "unpaired" });
      return;
    }
    if (current.status === "paired") current.remote.discardQueued();
    const forgotten = current.status === "paired" && (await current.remote.connection.call((client) => client["device.forget"]({}))).ok;
    this.close();
    await stopAlertWatch();
    await forgetCalmAction();
    const revoked = (await clearCredentials(forgotten)) || forgotten;
    this.pairing.set({
      busy: false,
      error: revoked ? null : "Unpaired here, but the Mac could not be reached. Revoke this device in Vitals on the Mac.",
    });
    this.session.set({ status: "unpaired" });
  }

  private open(credentials: Credentials, deviceKey: KeyPair | null): void {
    this.close();
    const remote = new Remote(
      credentials,
      deviceKey,
      openSocket,
      (alert) => {
        if (AppState.currentState === "active") void markAlertsSeen([alert]);
        else void notifyOnce(alert);
      },
      (next) => void saveCredentials(next).catch(() => undefined),
    );
    let active = true;
    void prepareNotifications().then(async (granted) => {
      if (granted && active) remote.record("info", "client.alerts.watch", { background: await startAlertWatch() });
    });
    const stopSeq = remote.connection.state.subscribe(() => {
      const state = remote.connection.state.get();
      if (state._tag === "Ready" && AppState.currentState === "active") void markAlertsSeen(state.hello.alerts);
    });
    let queuedCalm: (() => void) | null = null;
    const calmDown = () => void remote.run({ _tag: "CalmDown", alertId: null });
    const stopCalm = onCalmAction(() => {
      if (remote.connection.state.get()._tag === "Ready") return calmDown();
      queuedCalm ??= remote.connection.state.subscribe(() => {
        if (remote.connection.state.get()._tag !== "Ready") return;
        queuedCalm?.();
        queuedCalm = null;
        calmDown();
      });
    });
    let suspendTimer: ReturnType<typeof setTimeout> | null = null;
    const appState = AppState.addEventListener("change", (next) => {
      if (next === "active") {
        void markAlertsSeen(remote.events.alerts.get());
        if (suspendTimer !== null) clearTimeout(suspendTimer);
        suspendTimer = null;
        remote.record("info", "client.app.fg");
        remote.connection.wake("foreground");
      } else if (suspendTimer === null) {
        remote.record("info", "client.app.bg");
        void remote.flush();
        suspendTimer = setTimeout(() => remote.connection.suspend(), SUSPEND_AFTER_MS);
      }
    });
    const network = Network.addNetworkStateListener((next) => {
      trackLocalNetwork(next);
      if (AppState.currentState === "active") remote.connection.wake("network");
    });
    const stopTunnelWatch = runTunnelOnDemand(remote.connection, () => remote.credentials);
    this.teardown = () => {
      active = false;
      stopTunnelWatch();
      if (suspendTimer !== null) clearTimeout(suspendTimer);
      appState.remove();
      network.remove();
      stopCalm();
      queuedCalm?.();
      stopSeq();
      remote.dispose();
    };
    this.session.set({ status: "paired", remote });
  }

  private close(): void {
    this.teardown?.();
    this.teardown = null;
  }
}

export const sessions = new SessionManager();

if (Platform.OS !== "web") {
  void Network.getNetworkStateAsync().then(trackLocalNetwork, () => undefined);
  Linking.addEventListener("url", ({ url }) => sessions.receive(parsePairingDeepLink(url)));
  if (AppState.currentState === "active") startNearby();
  AppState.addEventListener("change", (state) => {
    if (state !== "active") return stopNearby();
    startNearby();
    void launchPairingLink().then((link) => sessions.receive(link));
  });
}
