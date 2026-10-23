/**
 * Dev-only: runs the real gateway against a fake Mac, so the phone app can be tested on an
 * emulator without a Mac. Feeds live samples, 25 agents, emulators, an open alert, and
 * applies commands (pause, calm, keep awake, shut down countdown) to its own state.
 *
 *   bun apps/gateway/scripts/fake-mac.ts
 *
 * Then pair the emulator with address http://10.0.2.2:47910 and the printed code.
 * A tiny proxy adds the tailnet identity header Tailscale would normally add.
 */
import { mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import type { ToApp } from "@vitals/contracts";
import { ToApp as ToAppSchema } from "@vitals/contracts";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Queue from "effect/Queue";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";

import { makeApp } from "../src/app.ts";
import { BridgeTransportService } from "../src/bridge/Bridge.ts";

const OWNER = "rafay@example.com";
const GATEWAY_PORT = 47_900;
const PROXY_PORT = 47_910;
const GB = 1024 ** 3;
const MB = 1024 ** 2;
const HOUR = 3_600_000;

const decodeToApp = Schema.decodeUnknownSync(Schema.fromJsonString(ToAppSchema));
const queue = Effect.runSync(Queue.unbounded<string>());
const emit = (message: object): void => void Effect.runSync(Queue.offer(queue, JSON.stringify(message)));
const wobble = (base: number, spread: number): number => Math.max(0, base + (Math.random() - 0.5) * spread);

const MAC = {
  name: "Rafay's MacBook Pro",
  model: "Mac15,8",
  chip: "Apple M3 Max",
  os: "macOS 26.1",
  coreCount: 14,
  memoryBytes: 36 * GB,
  hasBattery: true,
  hasFans: true,
  vitalsVersion: "0.214",
  channel: "dev",
};

interface Proc {
  pid: number;
  startTimeMs: number;
  name: string;
  group: "agents" | "emulators" | "devServers" | "browsers" | "other" | "protected";
  cpuPercent: number;
  memoryBytes: number;
  throttled: boolean;
  paused: boolean;
}

const started = Date.now() - 2 * HOUR;
const AGENTS = ["claude", "codex", "claude", "gemini", "claude", "codex", "opencode"];
const procs: Array<Proc> = [
  ...Array.from({ length: 25 }, (_, index): Proc => ({ pid: 30_000 + index, startTimeMs: started, name: AGENTS[index % AGENTS.length] ?? "claude", group: "agents", cpuPercent: 38 * 0.82 ** index, memoryBytes: 1.2 * GB * 0.88 ** index, throttled: false, paused: false })),
  { pid: 9001, startTimeMs: started, name: "qemu-system-aarch64", group: "emulators", cpuPercent: 61, memoryBytes: 4 * GB, throttled: false, paused: false },
  { pid: 9002, startTimeMs: started, name: "Simulator", group: "emulators", cpuPercent: 3, memoryBytes: 1.1 * GB, throttled: false, paused: false },
  { pid: 9101, startTimeMs: started, name: "node (vite)", group: "devServers", cpuPercent: 4, memoryBytes: 410 * MB, throttled: false, paused: false },
  { pid: 9102, startTimeMs: started, name: "bun dev", group: "devServers", cpuPercent: 2, memoryBytes: 180 * MB, throttled: false, paused: false },
  { pid: 501, startTimeMs: started, name: "Safari", group: "browsers", cpuPercent: 4, memoryBytes: 820 * MB, throttled: false, paused: false },
  { pid: 9201, startTimeMs: started, name: "Google Chrome Helper", group: "browsers", cpuPercent: 6, memoryBytes: 640 * MB, throttled: false, paused: false },
  { pid: 502, startTimeMs: started, name: "Xcode", group: "other", cpuPercent: 12, memoryBytes: 3.1 * GB, throttled: false, paused: false },
  { pid: 503, startTimeMs: started, name: "Slack", group: "other", cpuPercent: 3, memoryBytes: 610 * MB, throttled: false, paused: false },
  { pid: 504, startTimeMs: started, name: "Figma", group: "other", cpuPercent: 2, memoryBytes: 900 * MB, throttled: false, paused: false },
  { pid: 505, startTimeMs: started, name: "Music", group: "other", cpuPercent: 1, memoryBytes: 310 * MB, throttled: false, paused: false },
  { pid: 9301, startTimeMs: started, name: "WindowServer", group: "other", cpuPercent: 9, memoryBytes: 410 * MB, throttled: false, paused: false },
  { pid: 9302, startTimeMs: started, name: "mds_stores", group: "other", cpuPercent: 3, memoryBytes: 180 * MB, throttled: false, paused: false },
  { pid: 9303, startTimeMs: started, name: "Spotlight", group: "other", cpuPercent: 1, memoryBytes: 90 * MB, throttled: false, paused: false },
  { pid: 1, startTimeMs: started, name: "kernel_task", group: "protected", cpuPercent: 6, memoryBytes: 50 * MB, throttled: false, paused: false },
];

const apps = [
  { pid: 501, bundleId: "com.apple.Safari", name: "Safari", active: true, hidden: false },
  { pid: 502, bundleId: "com.apple.dt.Xcode", name: "Xcode", active: false, hidden: false },
  { pid: 503, bundleId: "com.tinyspeck.slackmacgap", name: "Slack", active: false, hidden: false },
  { pid: 504, bundleId: "com.figma.Desktop", name: "Figma", active: false, hidden: false },
  { pid: 505, bundleId: "com.apple.Music", name: "Music", active: false, hidden: true },
];
const emulators = [
  { kind: "android", id: "emulator-5554", name: "Pixel 9", pid: 9001 },
  { kind: "ios", id: "8E1F0C6A-2B9D-4C1E-9A77-3C1D5E0B2F41", name: "iPhone 17", pid: 9002 },
];

let keepAwake = { active: false, display: false, until: null as number | null, whileProcess: null as { pid: number; startTimeMs: number } | null };
let calmApplied = false;
let guardSettings = {
  enabled: true,
  cooldownSeconds: 300,
  rules: [
    { kind: "memoryPressure", enabled: true, threshold: 1, holdSeconds: 30 },
    { kind: "swapGrowth", enabled: true, threshold: 4, holdSeconds: 60 },
    { kind: "cpuSaturated", enabled: true, threshold: 90, holdSeconds: 120 },
    { kind: "agentOverload", enabled: true, threshold: 8, holdSeconds: 60 },
    { kind: "emulatorStack", enabled: false, threshold: 2, holdSeconds: 60 },
    { kind: "thermal", enabled: true, threshold: 2, holdSeconds: 30 },
  ],
};

const totals = () =>
  (["agents", "emulators", "devServers", "browsers", "other", "protected"] as const).map((group) => {
    const rows = procs.filter((proc) => proc.group === group);
    return { group, count: rows.length, cpuPercent: rows.reduce((sum, row) => sum + row.cpuPercent, 0), memoryBytes: rows.reduce((sum, row) => sum + row.memoryBytes, 0) };
  });

const agentAlert = {
  id: "alert-agents-1",
  rule: "agentOverload",
  severity: "warning",
  summary: "25 agents running",
  raisedAt: Date.now() - 20 * 60_000,
  clearedAt: null,
  groups: [],
  plan: { actions: [], summary: "Lower the priority of 25 agent processes" },
};
let alertOpen = true;

const guardState = () => ({
  settings: guardSettings,
  pressure: "warning",
  thermal: "fair",
  swapUsedBytes: 2.1 * GB,
  groups: totals(),
  active: alertOpen ? [agentAlert] : [],
  calmApplied,
});

let seq = 0;
const sample = () => {
  seq += 1;
  const busy = calmApplied ? 0.55 : 1;
  const cores = Array.from({ length: 14 }, (_, id) => ({ id, percent: Math.min(100, wobble(70 * busy, 40)), isPerformance: id >= 4 }));
  return {
    seq,
    at: Date.now(),
    cpu: { overall: Math.min(100, wobble(71 * busy, 14)), performance: Math.min(100, wobble(80 * busy, 12)), efficiency: Math.min(100, wobble(40, 20)), perCore: cores },
    gpu: { utilization: wobble(18, 10), memoryUsedBytes: 2.3 * GB, coreCount: 30 },
    thermal: { state: "fair", cpuC: wobble(calmApplied ? 56 : 68, 4), gpuC: wobble(52, 4), storageC: 41, batteryC: 33, sensors: [] },
    fans: [
      { id: 0, rpm: wobble(calmApplied ? 1320 : 2410, 120), minRpm: 1200, maxRpm: 5800 },
      { id: 1, rpm: wobble(calmApplied ? 1300 : 2380, 120), minRpm: 1200, maxRpm: 5800 },
    ],
    memory: { totalBytes: 36 * GB, usedBytes: wobble(29.4 * GB, 0.4 * GB), appBytes: 18 * GB, wiredBytes: 4 * GB, compressedBytes: 3 * GB, cachedBytes: 4 * GB, freeBytes: 2 * GB, swapUsedBytes: 2.1 * GB, swapTotalBytes: 4 * GB, pressure: "warning" },
    battery: { percent: 82, charging: false, externalPower: false, watts: wobble(-23, 4), timeRemainingMinutes: 190, cycleCount: 212, healthPercent: 94, temperatureC: 33, condition: "Normal" },
    power: { cpuWatts: wobble(16 * busy, 4), gpuWatts: wobble(4, 2), aneWatts: 0.2 },
    network: { inBytesPerSec: wobble(2.1 * MB, MB), outBytesPerSec: wobble(300_000, 200_000), wifiRssi: -52, primaryInterface: "en0" },
    disk: { readBytesPerSec: wobble(4 * MB, 3 * MB), writeBytesPerSec: wobble(2 * MB, 2 * MB) },
  };
};

const processes = (sortBy: "cpu" | "memory", limit: number) => {
  for (const proc of procs) proc.cpuPercent = proc.paused ? 0 : wobble(proc.cpuPercent || 1, proc.cpuPercent * 0.2);
  const rows = [...procs].sort((left, right) => (sortBy === "cpu" ? right.cpuPercent - left.cpuPercent : right.memoryBytes - left.memoryBytes)).slice(0, limit);
  return { at: Date.now(), rows, groups: totals() };
};

let need: Extract<ToApp, { t: "need" }> | null = null;
setInterval(() => {
  if (need === null) return;
  if (need.topics.length > 0) emit({ t: "sample", data: sample() });
  if (need.processes !== null) emit({ t: "processes", data: processes(need.processes.sortBy, need.processes.limit) });
  if (need.guard) emit({ t: "guard", data: guardState() });
}, 2_000);

const issued = new Map<string, { readonly kind: string; readonly deviceId: string }>();
const timers = new Map<string, ReturnType<typeof setTimeout>>();

const receipt = (id: string, kind: string, deviceId: string, status: string, deadlineAt: number | null) =>
  emit({ t: "receipt", receipt: { id, kind, deviceId, status, createdAt: Date.now(), deadlineAt, finishedAt: status === "pending" ? null : Date.now(), error: null } });

const setKeepAwake = (next: typeof keepAwake) => {
  keepAwake = next;
  emit({ t: "event", event: { _tag: "KeepAwakeChanged", at: Date.now(), state: keepAwake } });
};

const removeProc = (pid: number | null) => {
  const index = procs.findIndex((proc) => proc.pid === pid);
  if (index >= 0) procs.splice(index, 1);
};

const apply = (message: Extract<ToApp, { t: "cmd" }>) => {
  const command = message.command;
  const done = () => receipt(message.id, command._tag, message.deviceId, "done", null);
  issued.set(message.id, { kind: command._tag, deviceId: message.deviceId });
  switch (command._tag) {
    case "Processes":
      for (const { target, action } of command.actions) {
        const proc = procs.find((item) => item.pid === target.pid);
        if (proc === undefined) continue;
        if (action === "pause" || action === "resume") proc.paused = action === "pause";
        if (action === "throttle" || action === "unthrottle") proc.throttled = action === "throttle";
        if (action === "terminate" || action === "kill") procs.splice(procs.indexOf(proc), 1);
      }
      return done();
    case "CalmDown":
      calmApplied = true;
      for (const proc of procs) if (proc.group === "agents") proc.throttled = true;
      return done();
    case "UndoCalm":
      calmApplied = false;
      for (const proc of procs) if (proc.group === "agents") proc.throttled = false;
      return done();
    case "KeepAwake":
      setKeepAwake({ active: true, display: command.display, until: command.until, whileProcess: command.whileProcess });
      return done();
    case "AllowSleep":
      setKeepAwake({ active: false, display: false, until: null, whileProcess: null });
      return done();
    case "QuitApp":
    case "ForceQuitApp": {
      const index = apps.findIndex((app) => app.pid === command.app.pid);
      if (index >= 0) apps.splice(index, 1);
      removeProc(command.app.pid);
      return done();
    }
    case "HideApp": {
      const app = apps.find((item) => item.pid === command.app.pid);
      if (app !== undefined) app.hidden = true;
      return done();
    }
    case "StopEmulator": {
      const index = emulators.findIndex((emulator) => emulator.id === command.id);
      if (index >= 0) removeProc(emulators.splice(index, 1)[0]?.pid ?? null);
      return done();
    }
    case "ShutDown":
    case "Restart":
    case "LogOut":
      receipt(message.id, command._tag, message.deviceId, "pending", Date.now() + command.graceSeconds * 1000);
      timers.set(message.id, setTimeout(() => done(), command.graceSeconds * 1000));
      return;
    default:
      return done();
  }
};

const historyFor = (input: { readonly series: ReadonlyArray<string>; readonly from: number; readonly to: number; readonly points: number }) => ({
  series: input.series.map((name) => ({
    name,
    buckets: Array.from({ length: input.points }, (_, index) => {
      const avg = wobble(50 + 20 * Math.sin(index / 9), 10);
      return { t: Math.round(input.from + ((input.to - input.from) * index) / input.points), min: avg * 0.8, avg, max: Math.min(100, avg * 1.2) };
    }),
  })),
});

const write = (line: string): void => {
  const message = decodeToApp(line);
  switch (message.t) {
    case "hello":
      emit({ t: "hello", v: 1, mac: MAC, keepAwake });
      // Give the gateway's event log a moment to subscribe before raising the alert.
      setTimeout(() => emit({ t: "event", event: { _tag: "AlertRaised", at: Date.now(), alert: agentAlert } }), 3_000);
      return;
    case "need":
      need = message;
      return;
    case "cmd":
      return apply(message);
    case "cancel": {
      clearTimeout(timers.get(message.id));
      const order = issued.get(message.id);
      receipt(message.id, order?.kind ?? "ShutDown", order?.deviceId ?? "unknown", "cancelled", null);
      return;
    }
    case "query": {
      const reply = (ok: object) => emit({ t: "result", id: message.id, ok, error: null });
      switch (message.q._tag) {
        case "Apps":
          return reply({ _tag: "Apps", result: { running: apps, emulators } });
        case "Clipboard":
          return reply({ _tag: "Clipboard", text: "Copied on the Mac at 22:40" });
        case "SetGuard":
          guardSettings = message.q.settings as typeof guardSettings;
          return reply({ _tag: "SetGuard", settings: guardSettings });
        case "History":
          return reply({ _tag: "History", result: historyFor(message.q.input) });
        default:
          return emit({ t: "result", id: message.id, ok: null, error: "not in fake" });
      }
    }
    case "adminResult":
      if (message.ok?._tag === "ListDevices") {
        for (const device of message.ok.devices) {
          if (device.scopes.length < 4) emit({ t: "admin", id: `scopes-${device.id}`, op: { _tag: "SetScopes", deviceId: device.id, scopes: ["read", "operate", "destructive", "clipboard"] } });
        }
      }
      if (message.ok?._tag === "CreatePairing") {
        console.log(`\nPair the emulator:\n  Mac address  http://10.0.2.2:${String(PROXY_PORT)}\n  Code         ${message.ok.code}\n`);
      }
      return;
    default:
      return;
  }
};

/** Kept between runs so a paired emulator stays paired after a restart. */
const dataDir = (): string => {
  const dir = join(tmpdir(), "vitals-fake-mac");
  mkdirSync(dir, { recursive: true });
  return dir;
};

const config = {
  channel: "dev" as const,
  port: GATEWAY_PORT,
  servePort: 7999,
  dataDir: dataDir(),
  webDir: null,
  tailscaleBin: null,
  manageServe: false,
  ownerLogin: OWNER,
  lanPort: null,
};

const transport = Layer.succeed(BridgeTransportService, { lines: Stream.fromQueue(queue), write, onClose: () => {} });
Effect.runFork(Layer.launch(makeApp(config, { transport })));

const upstream = `127.0.0.1:${String(GATEWAY_PORT)}`;

// Loopback only by default: the proxy signs every request in as the owner, over plain HTTP. The
// emulator reaches it as 10.0.2.2. For a real phone on the LAN, opt in with FAKE_MAC_HOST=0.0.0.0.
Bun.serve<{ readonly path: string; socket: WebSocket | null; pending: Array<string | ArrayBuffer> }>({
  hostname: process.env["FAKE_MAC_HOST"] ?? "127.0.0.1",
  port: PROXY_PORT,
  fetch(request, server) {
    const url = new URL(request.url);
    if (request.headers.get("upgrade") === "websocket") {
      return server.upgrade(request, { data: { path: `${url.pathname}${url.search}`, socket: null, pending: [] } }) ? undefined : new Response("upgrade failed", { status: 400 });
    }
    const headers = new Headers(request.headers);
    headers.set("tailscale-user-login", OWNER);
    headers.delete("host");
    return fetch(`http://${upstream}${url.pathname}${url.search}`, { method: request.method, headers, body: request.body });
  },
  websocket: {
    open(client) {
      const socket = new WebSocket(`ws://${upstream}${client.data.path}`, { headers: { "tailscale-user-login": OWNER } });
      socket.binaryType = "arraybuffer";
      client.data.socket = socket;
      socket.addEventListener("open", () => {
        for (const message of client.data.pending) socket.send(message);
        client.data.pending = [];
      });
      socket.addEventListener("message", (event) => client.send(event.data as string | ArrayBuffer));
      socket.addEventListener("close", () => client.close());
    },
    message(client, message) {
      const data = typeof message === "string" ? message : message.buffer.slice(message.byteOffset, message.byteOffset + message.byteLength);
      const socket = client.data.socket;
      if (socket !== null && socket.readyState === WebSocket.OPEN) socket.send(data);
      else client.data.pending.push(data as string | ArrayBuffer);
    },
    close(client) {
      client.data.socket?.close();
    },
  },
});

setTimeout(() => emit({ t: "admin", id: "pair-1", op: { _tag: "CreatePairing" } }), 1_000);
// Every paired test phone gets every permission, so destructive flows can be tested too.
setInterval(() => emit({ t: "admin", id: `devices-${String(Date.now())}`, op: { _tag: "ListDevices" } }), 5_000);
console.log(`Fake Mac running. Gateway on ${upstream}, phone proxy on 0.0.0.0:${String(PROXY_PORT)}.`);
