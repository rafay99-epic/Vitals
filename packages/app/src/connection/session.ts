import { type ConnectionOptions, pair, parsePairingUrl, type PairingLink, Store } from "@vitals/client-runtime";
import * as Network from "expo-network";
import { AppState, Platform } from "react-native";

import { deviceInfo } from "../lib/device.ts";
import { notifyAlert, onCalmAction, prepareNotifications, pushToken } from "../notifications/alerts";
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

const webPairingLink = (): PairingLink | null =>
  Platform.OS === "web" && typeof globalThis.location !== "undefined" ? parsePairingUrl(globalThis.location.href) : null;

class SessionManager {
  readonly session = new Store<Session>({ status: "loading" });
  readonly pairing = new Store<PairingState>({ busy: false, error: null });
  private teardown: (() => void) | null = null;
  private started = false;

  start(): void {
    if (this.started) return;
    this.started = true;
    void (async () => {
      const link = webPairingLink();
      if (link !== null && (await this.pairWith(link))) return;
      const credentials = await loadCredentials();
      if (credentials === null) this.session.set({ status: "unpaired" });
      else this.open(credentials);
    })();
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
    await saveCredentials(credentials);
    this.pairing.set({ busy: false, error: null });
    this.open(credentials);
    return true;
  }

  async forget(): Promise<void> {
    this.close();
    await clearCredentials();
    this.session.set({ status: "unpaired" });
  }

  private open(credentials: Credentials): void {
    this.close();
    const remote = new Remote(credentials, openSocket, (alert) => {
      if (AppState.currentState !== "active") void notifyAlert(alert);
    });
    void prepareNotifications().then(async (granted) => {
      if (!granted) return;
      const token = await pushToken();
      if (token !== null) await remote.connection.call((client) => client["push.register"]({ token }));
    });
    const stopCalm = onCalmAction(() => void remote.run({ _tag: "CalmDown", alertId: null }));
    let suspendTimer: ReturnType<typeof setTimeout> | null = null;
    const appState = AppState.addEventListener("change", (next) => {
      if (next === "active") {
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
    const network = Network.addNetworkStateListener(() => remote.connection.wake("network"));
    this.teardown = () => {
      if (suspendTimer !== null) clearTimeout(suspendTimer);
      appState.remove();
      network.remove();
      stopCalm();
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
