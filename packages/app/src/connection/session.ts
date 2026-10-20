import { type ConnectionOptions, pair, parsePairingDeepLink, parsePairingUrl, type PairingLink, Store, unpair } from "@vitals/client-runtime";
import * as Network from "expo-network";
import { AppState, Linking, Platform } from "react-native";

import { deviceInfo } from "../lib/device.ts";
import { forgetCalmAction, onCalmAction, prepareNotifications } from "../notifications/alerts";
import { markAlertsSeen, notifyOnce, startAlertWatch, stopAlertWatch } from "../notifications/background";
import { clearCredentials, loadCredentials, saveCredentials } from "../persistence/credentials";
import type { Credentials } from "../persistence/credentialsSchema.ts";
import { Remote } from "../state/remote.ts";

const SUSPEND_AFTER_MS = 10_000;

export type Session =
  | { readonly status: "loading" }
  | { readonly status: "unpaired" }
  | { readonly status: "paired"; readonly remote: Remote };

export interface PairingState {
  readonly busy: boolean;
  readonly error: string | null;
}

const openSocket: ConnectionOptions["webSocket"] = (url, options) =>
  new WebSocket(url, typeof options === "string" || Array.isArray(options) ? options : undefined);

const launchPairingLink = async (): Promise<PairingLink | null> => {
  if (Platform.OS === "web") return typeof globalThis.location === "undefined" ? null : parsePairingUrl(globalThis.location.href);
  const initial = await Linking.getInitialURL();
  return typeof initial === "string" ? parsePairingDeepLink(initial) : null;
};

class SessionManager {
  readonly session = new Store<Session>({ status: "loading" });
  readonly pairing = new Store<PairingState>({ busy: false, error: null });
  private teardown: (() => void) | null = null;
  private started = false;
  private readonly usedCodes = new Set<string>();

  handleLink(link: PairingLink | null): Promise<boolean> {
    if (link === null || this.usedCodes.has(link.code)) return Promise.resolve(false);
    this.usedCodes.add(link.code);
    return this.pairWith(link);
  }

  start(): void {
    if (this.started) return;
    this.started = true;
    void (async () => {
      if (await this.handleLink(await launchPairingLink())) return;
      const credentials = await loadCredentials();
      if (this.session.get().status === "paired") return;
      if (credentials === null) this.session.set({ status: "unpaired" });
      else this.open(credentials);
    })().catch((error: unknown) => {
      this.pairing.set({ busy: false, error: error instanceof Error ? error.message : "Could not read this device's pairing. Pair again." });
      this.session.set({ status: "unpaired" });
    });
  }

  async pairWith(link: PairingLink): Promise<boolean> {
    this.pairing.set({ busy: true, error: null });
    const outcome = await pair(link, deviceInfo());
    if (!outcome.ok) {
      this.pairing.set({ busy: false, error: outcome.message });
      if (this.session.get().status === "loading") this.session.set({ status: "unpaired" });
      return false;
    }
    if (Platform.OS === "web") globalThis.history?.replaceState(null, "", "/");
    const credentials: Credentials = {
      baseUrl: link.baseUrl,
      token: outcome.response.token,
      deviceId: outcome.response.deviceId,
      scopes: outcome.response.scopes,
      pairedAt: Date.now(),
    };
    const previous = Platform.OS === "web" ? null : await loadCredentials().catch(() => null);
    await saveCredentials(credentials);
    if (previous !== null && previous.deviceId !== credentials.deviceId) void unpair(previous.baseUrl, previous.token);
    this.pairing.set({ busy: false, error: null });
    this.open(credentials);
    return true;
  }

  async forget(): Promise<void> {
    const current = this.session.get();
    if (Platform.OS === "web") {
      if (!(await clearCredentials())) {
        if (current.status === "paired") current.remote.show("Could not reach your Mac to unpair. Try again.", "bad");
        return;
      }
      this.close();
      this.session.set({ status: "unpaired" });
      return;
    }
    if (current.status === "paired") current.remote.discardQueued();
    this.close();
    await stopAlertWatch();
    await forgetCalmAction();
    const revoked = await clearCredentials();
    this.pairing.set({
      busy: false,
      error: revoked ? null : "Unpaired here, but the Mac could not be reached. Revoke this device in Vitals on the Mac.",
    });
    this.session.set({ status: "unpaired" });
  }

  private open(credentials: Credentials): void {
    this.close();
    const remote = new Remote(credentials, openSocket, (alert) => {
      if (AppState.currentState === "active") void markAlertsSeen([alert]);
      else void notifyOnce(alert);
    });
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
    const network = Network.addNetworkStateListener(() => {
      if (AppState.currentState === "active") remote.connection.wake("network");
    });
    this.teardown = () => {
      active = false;
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
  Linking.addEventListener("url", ({ url }) => void sessions.handleLink(parsePairingDeepLink(url)));
  AppState.addEventListener("change", (state) => {
    if (state === "active") void launchPairingLink().then((link) => sessions.handleLink(link));
  });
}
