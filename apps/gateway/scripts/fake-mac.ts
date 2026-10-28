/**
 * Dev-only: runs the real gateway against a fake Mac, so the phone app can be tested on an
 * emulator without a Mac. Feeds live samples, 25 agents, emulators, an open alert, and
 * applies commands (pause, calm, keep awake, shut down countdown) to its own state.
 *
 *   bun apps/gateway/scripts/fake-mac.ts             # busy: 25 agents and an open alert
 *   FAKE_MAC_SCENE=calm bun apps/gateway/scripts/fake-mac.ts   # calm: light load, no alert
 *
 * Then pair the emulator with address http://10.0.2.2:47910 and the printed code.
 * A tiny proxy adds the tailnet identity header Tailscale would normally add.
 *
 * Clipboard history is on and seeded with a text, a long command, two links, an image, a file, and
 * a folder. `kill -WINCH <pid>` copies something new on the "Mac" (text, link, image in turn).
 *
 * Drop: files phones send are accepted and moved into `<data dir>/received/`. The drop control port
 * (printed at start) sends real files to every paired phone and steers drops:
 *
 *   curl -X POST 'http://127.0.0.1:47940/send?path=/path/to/file-or-folder'
 *   curl -X POST 'http://127.0.0.1:47940/pause?id=<dropId>'    # also resume, cancel, accept, decline
 *   curl http://127.0.0.1:47940/drops
 *
 * FAKE_MAC_ASK=1 makes the "Mac" ask before taking files instead of accepting them.
 */
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, extname, join, relative } from "node:path";
import { deflateSync } from "node:zlib";

import type { Device, Drop, MacDropFile, ToApp } from "@vitals/contracts";
import { DROP_LAN_TLS_OFFSET, ToApp as ToAppSchema } from "@vitals/contracts";
import { newId } from "@vitals/shared";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Queue from "effect/Queue";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";

import { makeApp } from "../src/app.ts";
import { BridgeTransportService } from "../src/bridge/Bridge.ts";
import { spkiPin } from "../src/drop/tls.ts";

const OWNER = "rafay@example.com";
const GATEWAY_PORT = 47_900;
const PROXY_PORT = 47_910;
const LAN_PORT = 47_920;
const DROP_CONTROL_PORT = 47_940;
const ASK = process.env["FAKE_MAC_ASK"] === "1";
const GB = 1024 ** 3;
const MB = 1024 ** 2;
const HOUR = 3_600_000;
const CALM = process.env["FAKE_MAC_SCENE"] === "calm";

const decodeToApp = Schema.decodeUnknownSync(Schema.fromJsonString(ToAppSchema));
const queue = Effect.runSync(Queue.unbounded<string>());
const emit = (message: object): void => void Effect.runSync(Queue.offer(queue, JSON.stringify(message)));
const ALL_SCOPES = ["read", "operate", "destructive", "clipboard", "files", "fsRead", "fsWrite", "terminal"] as const;

// SIGHUP plays the Mac's own volume keys: it steps the volume so phones can be seen following.
let audio = { volume: 0.4 as number | null, muted: false as boolean | null };
process.on("SIGHUP", () => {
  audio = { ...audio, volume: Math.round((((audio.volume ?? 0) + 0.1) % 1) * 100) / 100 };
  emit({ t: "audio", data: audio });
});

const wobble = (base: number, spread: number): number => Math.max(0, base + (Math.random() - 0.5) * spread);

const networkSample = (down: number, up: number) => ({
  inBytesPerSec: down,
  outBytesPerSec: up,
  wifiRssi: -52,
  primaryInterface: "en0",
  totalInBytes: 48.2 * GB,
  totalOutBytes: 6.1 * GB,
  links: [
    { name: "en0", label: "Wi-Fi", kind: "wifi" as const, inBytesPerSec: down, outBytesPerSec: up, active: true },
    { name: "en5", label: "Ethernet", kind: "ethernet" as const, inBytesPerSec: 0, outBytesPerSec: 0, active: false },
  ],
  wifi: { ssid: "Home-5G", rssi: -52, noise: -92, txRateMbps: 1201, channel: 149, band: "5 GHz" },
});

const MAC = {
  name: "MacBook Pro",
  model: "Mac15,8",
  chip: "Apple M4",
  os: "macOS 27.0",
  coreCount: 10,
  memoryBytes: 16 * GB,
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
  // The calm scene is the same Mac at rest: two idle agents and no emulator running.
  ...Array.from({ length: CALM ? 2 : 25 }, (_, index): Proc => ({ pid: 30_000 + index, startTimeMs: started, name: AGENTS[index % AGENTS.length] ?? "claude", group: "agents", cpuPercent: 38 * 0.82 ** index, memoryBytes: 1.2 * GB * 0.88 ** index, throttled: false, paused: false })),
  ...(CALM
    ? []
    : [
        { pid: 9001, startTimeMs: started, name: "qemu-system-aarch64", group: "emulators", cpuPercent: 61, memoryBytes: 4 * GB, throttled: false, paused: false } satisfies Proc,
        { pid: 9002, startTimeMs: started, name: "Simulator", group: "emulators", cpuPercent: 3, memoryBytes: 1.1 * GB, throttled: false, paused: false } satisfies Proc,
      ]),
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
const emulators = CALM
  ? []
  : [
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
let alertOpen = !CALM;

const guardState = () => ({
  settings: guardSettings,
  pressure: CALM ? "normal" : "warning",
  thermal: CALM ? "nominal" : "fair",
  swapUsedBytes: (CALM ? 0.3 : 2.1) * GB,
  groups: totals(),
  active: alertOpen ? [agentAlert] : [],
  calmApplied,
});

let seq = 0;
const sample = () => {
  seq += 1;
  const busy = CALM ? 0.42 : calmApplied ? 0.55 : 1;
  const cores = Array.from({ length: 10 }, (_, id) => ({ id, percent: Math.min(100, wobble(70 * busy, 40)), isPerformance: id >= 6 }));
  return {
    seq,
    at: Date.now(),
    cpu: { overall: Math.min(100, wobble(71 * busy, 14)), performance: Math.min(100, wobble(80 * busy, 12)), efficiency: Math.min(100, wobble(40, 20)), perCore: cores },
    gpu: { utilization: CALM ? wobble(1, 1) : wobble(18, 10), memoryUsedBytes: 2.3 * GB, coreCount: 30, rendererUtilization: wobble(14, 8), tilerUtilization: wobble(7, 5), memoryTotalBytes: 27 * GB },
    thermal: { state: CALM ? "nominal" : "fair", cpuC: wobble(CALM ? 47 : calmApplied ? 56 : 68, 2), gpuC: wobble(52, 4), storageC: 41, batteryC: 33, sensors: [] },
    // Same Mac in both scenes; at rest its fans are simply off, and say so.
    fans: [
      { id: 0, rpm: CALM ? 0 : wobble(calmApplied ? 1320 : 2410, 120), minRpm: 1200, maxRpm: 5800 },
      { id: 1, rpm: CALM ? 0 : wobble(calmApplied ? 1300 : 2380, 120), minRpm: 1200, maxRpm: 5800 },
    ],
    memory: { totalBytes: 16 * GB, usedBytes: wobble((CALM ? 12.4 : 14.1) * GB, 0.2 * GB), appBytes: 8 * GB, wiredBytes: 2.5 * GB, compressedBytes: 1.5 * GB, cachedBytes: 2 * GB, freeBytes: 1 * GB, swapUsedBytes: (CALM ? 0.3 : 2.1) * GB, swapTotalBytes: 4 * GB, pressure: CALM ? "normal" : "warning" },
    battery: { percent: 85, charging: CALM, externalPower: CALM, watts: CALM ? wobble(23, 4) : wobble(-23, 4), timeRemainingMinutes: 190, cycleCount: 212, healthPercent: 94, temperatureC: 33, condition: "Normal", fullyCharged: false, designCapacityMah: 7594, maxCapacityMah: 7139, remainingCapacityMah: 4420, designCycleCount: 1000, voltage: 12.7, amperage: CALM ? 1.8 : -1.8, ...(CALM ? { adapter: { watts: 96, name: "96W USB-C Power Adapter", wireless: false, deliveredWatts: 41.2, voltage: 20, amperage: 2.06 } } : {}) },
    power: { cpuWatts: wobble(16 * busy, 4), gpuWatts: wobble(4, 2), aneWatts: 0.2 },
    systemWatts: wobble(28 * busy, 6),
    network: networkSample(wobble(2.1 * MB, MB), wobble(300_000, 200_000)),
    disk: { readBytesPerSec: wobble(4 * MB, 3 * MB), writeBytesPerSec: wobble(2 * MB, 2 * MB), freeBytes: 412 * GB, totalBytes: 994 * GB, volume: "Macintosh HD", health: { model: "APPLE SSD AP1024Z", wearPercent: 3, readBytes: 61e12, writtenBytes: 38e12, powerOnHours: 2140, unsafeShutdowns: 6, sparePercent: 100, celsius: 41, warning: false } },
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
    case "SetVolume":
      audio = { ...audio, volume: command.level };
      emit({ t: "audio", data: audio });
      return done();
    case "SetMuted":
      audio = { ...audio, muted: command.muted };
      emit({ t: "audio", data: audio });
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

/* ---------- clipboard ---------- */

const pngChunk = (type: string, data: Uint8Array): Buffer => {
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const head = Buffer.alloc(4);
  head.writeUInt32BE(data.length);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(Bun.hash.crc32(body) >>> 0);
  return Buffer.concat([head, body, crc]);
};

/** A real RGB PNG: a diagonal gradient in the given tint, so each one hashes differently. */
const gradientPng = (size: number, tint: readonly [number, number, number]): Buffer => {
  const row = size * 3 + 1;
  const raw = Buffer.alloc(row * size);
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const shade = (x + y) / (2 * size);
      tint.forEach((channel, index) => {
        raw[y * row + 1 + x * 3 + index] = Math.round(channel * shade);
      });
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header.set([8, 2, 0, 0, 0], 8);
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", header),
    pngChunk("IDAT", deflateSync(raw)),
    pngChunk("IEND", new Uint8Array(0)),
  ]);
};

const clipsDir = (): string => join(dataDir(), "clips");

/** Sample files the "Mac" copied in Finder, so downloads exercise ClipMaterialize. */
const originDir = (): string => {
  const dir = join(tmpdir(), "vitals-fake-mac-origin");
  mkdirSync(join(dir, "Invoices"), { recursive: true });
  writeFileSync(join(dir, "release-notes.md"), "# Vitals 0.214\n\n- Clipboard and Drop\n- Faster history\n");
  for (const month of ["2026-07", "2026-08", "2026-09"]) writeFileSync(join(dir, "Invoices", `invoice-${month}.txt`), `Invoice ${month}\nTotal: 120.00\n`);
  return dir;
};

const macClip = (fields: Record<string, unknown>) => ({
  id: newId(),
  at: Date.now(),
  source: "Terminal",
  text: null,
  truncated: false,
  name: null,
  mime: null,
  bytes: 0,
  files: null,
  thumb: null,
  stored: null,
  origin: null,
  ...fields,
});

const textClip = (text: string, source: string, at = Date.now()) => macClip({ kind: "text", text, source, at });
const linkClip = (url: string, source: string, at = Date.now()) => macClip({ kind: "link", text: url, source, at });

const imageClip = (tint: readonly [number, number, number], at = Date.now()) => {
  const id = newId();
  const png = gradientPng(96, tint);
  mkdirSync(clipsDir(), { recursive: true });
  writeFileSync(join(clipsDir(), `${id}.png`), png);
  return macClip({ id, kind: "image", at, source: "Preview", name: "Screenshot.png", mime: "image/png", bytes: png.length, thumb: gradientPng(32, tint).toString("base64"), stored: `${id}.png` });
};

const emitClip = (clip: object) => emit({ t: "clip", clip });

const seedClips = () => {
  const origin = originDir();
  const minutesAgo = (minutes: number) => Date.now() - minutes * 60_000;
  const notes = join(origin, "release-notes.md");
  emit({ t: "clipPolicy", policy: { enabled: true, keepDays: 7 } });
  emitClip(textClip("Meet at 6 at the usual place", "Messages", minutesAgo(90)));
  emitClip(
    textClip(
      "xcodebuild -scheme Vitals -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY='Vitals Local Signing' clean build | xcbeautify",
      "Terminal",
      minutesAgo(60),
    ),
  );
  emitClip(linkClip("https://github.com/rafay99-epic/Vitals/releases", "Safari", minutesAgo(45)));
  emitClip(linkClip("https://developer.apple.com/documentation/appkit/nspasteboard", "Safari", minutesAgo(30)));
  emitClip(imageClip([255, 120, 40], minutesAgo(20)));
  emitClip(macClip({ kind: "file", at: minutesAgo(10), source: "Finder", name: basename(notes), mime: "text/markdown", bytes: statSync(notes).size, origin: notes }));
  emitClip(macClip({ kind: "folder", at: minutesAgo(5), source: "Finder", name: "Invoices", files: 3, origin: join(origin, "Invoices") }));
};

/** Clones a copied file, or zips a copied folder, into clips/ the way the Mac app does. */
const materialize = async (q: { readonly id: string; readonly kind: "file" | "folder"; readonly origin: string }) => {
  mkdirSync(clipsDir(), { recursive: true });
  if (q.kind === "file") {
    const ext = (q.origin.split(".").pop() ?? "").toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 8) || "bin";
    const stored = `${q.id}.${ext}`;
    copyFileSync(q.origin, join(clipsDir(), stored));
    return { _tag: "ClipMaterialize", stored, bytes: statSync(join(clipsDir(), stored)).size, files: null };
  }
  const stored = `${q.id}.zip`;
  const zipped = Bun.spawn(["ditto", "-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--keepParent", q.origin, join(clipsDir(), stored)]);
  if ((await zipped.exited) !== 0) throw new Error("ditto failed");
  return { _tag: "ClipMaterialize", stored, bytes: statSync(join(clipsDir(), stored)).size, files: readdirSync(q.origin).length };
};

const write = (line: string): void => {
  const message = decodeToApp(line);
  switch (message.t) {
    case "hello":
      emit({ t: "hello", v: 1, mac: MAC, keepAwake });
      emit({ t: "audio", data: audio });
      // Give the gateway's event log a moment to subscribe before raising the alert.
      if (alertOpen) setTimeout(() => emit({ t: "event", event: { _tag: "AlertRaised", at: Date.now(), alert: agentAlert } }), 3_000);
      seedClips();
      if (ASK) emit({ t: "dropPolicy", policy: { autoAccept: false, askWeb: true, maxBytes: 50 * GB } });
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
        case "ClipMaterialize":
          materialize(message.q).then(reply, (error: unknown) => emit({ t: "result", id: message.id, ok: null, error: String(error) }));
          return;
        case "ClipPut":
          console.log(`ClipPut from ${message.q.deviceName}: ${String(message.q.items.length)} to ${message.q.to}`, message.q.items.map((item) => item.stored ?? item.text?.slice(0, 40)));
          return reply({ _tag: "ClipPut", placed: message.q.items.length });
        case "FsThumbs": {
          const paths = message.q.paths;
          void Promise.all(paths.map(async (path) => ({ path, jpeg: /\.jpe?g$/i.test(path) ? Buffer.from(await Bun.file(path).arrayBuffer()).toString("base64") : null }))).then((thumbs) =>
            reply({ _tag: "FsThumbs", thumbs }),
          );
          return;
        }
        case "FsOpen":
          console.log(`FsOpen ${message.q.path} (fake)`);
          return reply({ _tag: "FsOpen" });
        default:
          return emit({ t: "result", id: message.id, ok: null, error: "not in fake" });
      }
    }
    case "drop":
      return onDrop(message.drop);
    case "dropRemoved":
      drops.delete(message.id);
      return;
    case "dropReceived":
      return takeDrop(message);
    case "adminResult":
      if (message.ok?._tag === "ListDevices") {
        phones = message.ok.devices.filter((device) => device.platform !== "web" && device.revokedAt === null);
        for (const device of message.ok.devices) {
          if (device.scopes.length < ALL_SCOPES.length) emit({ t: "admin", id: `scopes-${device.id}`, op: { _tag: "SetScopes", deviceId: device.id, scopes: [...ALL_SCOPES] } });
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

/* ---------- drop ---------- */

let phones: ReadonlyArray<Omit<Device, "connected">> = [];
const drops = new Map<string, Drop>();

const onDrop = (drop: Drop) => {
  const previous = drops.get(drop.id);
  drops.set(drop.id, drop);
  if (previous?.state !== drop.state) {
    const peer = drop.from._tag === "Device" ? `from ${drop.from.name}` : `to ${drop.to._tag === "Device" ? drop.to.name : "Mac"}`;
    console.log(`Drop ${drop.id} ${peer}: ${drop.state}${drop.error === null ? "" : ` (${drop.error})`}, ${String(drop.files.length)} files, ${String(drop.bytes)} bytes`);
  }
  if (!ASK && drop.state === "asking" && drop.from._tag === "Device") emit({ t: "dropDecision", id: drop.id, accept: true });
};

const freeName = (path: string): string => {
  if (!existsSync(path)) return path;
  const extension = extname(path);
  for (let copy = 2; ; copy += 1) {
    const candidate = `${path.slice(0, path.length - extension.length)} ${String(copy)}${extension}`;
    if (!existsSync(candidate)) return candidate;
  }
};

const takeDrop = (message: Extract<ToApp, { t: "dropReceived" }>) => {
  const inbox = join(dataDir(), "received");
  for (const file of message.files) {
    const staged = join(dataDir(), "drop", file.stored);
    if (!existsSync(staged)) continue;
    const target = freeName(join(inbox, file.path ?? file.name));
    mkdirSync(dirname(target), { recursive: true });
    renameSync(staged, target);
    console.log(`Received ${target} (${String(file.size)} bytes) from ${message.from._tag === "Device" ? message.from.name : "Mac"}`);
  }
};

const filesAt = (path: string): ReadonlyArray<MacDropFile> => {
  const info = statSync(path);
  const entry = (full: string, relativePath: string | null): MacDropFile => ({
    name: basename(full),
    path: relativePath,
    size: statSync(full).size,
    mime: Bun.file(full).type.split(";")[0] ?? null,
    origin: full,
  });
  if (info.isFile()) return [entry(path, null)];
  return readdirSync(path, { recursive: true, withFileTypes: true })
    .filter((item) => item.isFile() && !item.name.startsWith("."))
    .map((item) => join(item.parentPath, item.name))
    .map((full) => entry(full, relative(dirname(path), full)));
};

const steer = (url: URL, act: (id: string) => object) => {
  const id = url.searchParams.get("id");
  if (id === null || !drops.has(id)) return Response.json({ error: "unknown drop id" }, { status: 404 });
  emit(act(id));
  return Response.json({ ok: true });
};

Bun.serve({
  hostname: "127.0.0.1",
  port: DROP_CONTROL_PORT,
  fetch(request) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/drops") return Response.json([...drops.values()]);
    if (request.method !== "POST") return new Response(null, { status: 405 });
    switch (url.pathname) {
      case "/send": {
        const paths = url.searchParams.getAll("path");
        if (paths.length === 0 || !paths.every((path) => existsSync(path))) return Response.json({ error: "pass ?path= with a file or folder that exists" }, { status: 400 });
        if (phones.length === 0) return Response.json({ error: "no paired phones yet" }, { status: 409 });
        const files = paths.flatMap(filesAt);
        emit({ t: "dropSend", to: phones.map((phone) => phone.id), files });
        return Response.json({ to: phones.map((phone) => phone.name), files: files.length });
      }
      case "/pause":
        return steer(url, (id) => ({ t: "dropPause", id, paused: true }));
      case "/resume":
        return steer(url, (id) => ({ t: "dropPause", id, paused: false }));
      case "/cancel":
        return steer(url, (id) => ({ t: "dropCancel", id }));
      case "/accept":
        return steer(url, (id) => ({ t: "dropDecision", id, accept: true }));
      case "/decline":
        return steer(url, (id) => ({ t: "dropDecision", id, accept: false }));
      default:
        return new Response(null, { status: 404 });
    }
  },
});

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
  // Point at `apps/web/dist` (after `pnpm --filter @vitals/web export`) to test the web client too.
  webDir: process.env["VITALS_REMOTE_WEB_DIR"] ?? null,
  tailscaleBin: null,
  manageServe: false,
  ownerLogin: OWNER,
  lanPort: LAN_PORT,
  ...(process.env["FAKE_MAC_HOME"] === undefined ? {} : { homeDir: process.env["FAKE_MAC_HOME"] }),
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

// For testing notifications: `kill -USR1 <pid>` raises a fresh alert, `kill -USR2 <pid>` clears the newest one.
const raised: Array<typeof agentAlert> = [];
process.on("SIGUSR1", () => {
  const alert = { ...agentAlert, id: `alert-agents-${String(Date.now())}`, raisedAt: Date.now() };
  raised.push(alert);
  emit({ t: "event", event: { _tag: "AlertRaised", at: Date.now(), alert } });
});
process.on("SIGUSR2", () => {
  const alert = raised.pop();
  if (alert !== undefined) emit({ t: "event", event: { _tag: "AlertCleared", at: Date.now(), alert: { ...alert, clearedAt: Date.now() } } });
});

// `kill -WINCH <pid>` copies something new on the "Mac", rotating text, link, image, to test live arrival and auto-copy.
let copies = 0;
process.on("SIGWINCH", () => {
  copies += 1;
  const stamp = new Date().toLocaleTimeString();
  const fresh = [
    () => textClip(`Copied on the Mac at ${stamp}`, "Notes"),
    () => linkClip(`https://vitals.rafay99.com/releases?copy=${String(copies)}`, "Safari"),
    () => imageClip([40 + ((copies * 70) % 215), 160, 255 - ((copies * 50) % 200)]),
  ][copies % 3];
  if (fresh !== undefined) emitClip(fresh());
});

setTimeout(() => emit({ t: "admin", id: "pair-1", op: { _tag: "CreatePairing" } }), 1_000);
// Every paired test phone gets every permission, so destructive flows can be tested too.
setInterval(() => emit({ t: "admin", id: `devices-${String(Date.now())}`, op: { _tag: "ListDevices" } }), 5_000);
console.log(`Fake Mac running. Gateway on ${upstream}, phone proxy on 0.0.0.0:${String(PROXY_PORT)}.`);
console.log(`Drop control on http://127.0.0.1:${String(DROP_CONTROL_PORT)} (POST /send?path=…). Received files land in ${join(dataDir(), "received")}.`);
setTimeout(() => {
  const cert = join(dataDir(), "drop-tls.crt");
  if (!existsSync(cert)) return console.log("Wi-Fi TLS is off: no certificate was made.");
  console.log(`Wi-Fi TLS on port ${String(LAN_PORT + DROP_LAN_TLS_OFFSET)}, pin ${spkiPin(readFileSync(cert))}`);
}, 1_500);
