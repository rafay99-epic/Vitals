import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { DeviceId } from "@vitals/contracts";
import * as Effect from "effect/Effect";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";

import { type Gateway, pairDevice, startGateway, withClient } from "./harness.ts";

const deviceIdOf = Schema.decodeUnknownSync(DeviceId);

let gateway: Gateway | null = null;
let home = "";
let outside = "";

const write = (path: string, text: string, mtime: number) => {
  writeFileSync(path, text);
  utimesSync(path, mtime, mtime);
};

beforeEach(() => {
  home = realpathSync(mkdtempSync(join(tmpdir(), "vitals-home-")));
  outside = realpathSync(mkdtempSync(join(tmpdir(), "vitals-outside-")));
  for (const folder of ["Desktop", "Downloads", "Downloads/Trip", "Downloads/Trip/day 2", "Library/Keychains"]) mkdirSync(join(home, folder), { recursive: true });
  write(join(home, "Downloads", "b.mov"), "movie-bytes", 2_000);
  write(join(home, "Downloads", "a.txt"), "a", 3_000);
  write(join(home, "Downloads", "file 10.txt"), "ten", 1_000);
  write(join(home, "Downloads", "file 9.txt"), "nine", 1_500);
  write(join(home, "Downloads", ".hidden"), "x", 1_000);
  write(join(home, "Downloads", "Trip", "one.jpg"), "jpeg-one", 1_000);
  write(join(home, "Downloads", "Trip", "day 2", "two.jpg"), "jpeg-two", 1_000);
  write(join(home, "Library", "Keychains", "login.keychain-db"), "secret", 1_000);
  write(join(outside, "elsewhere.txt"), "nope", 1_000);
  symlinkSync(outside, join(home, "Downloads", "Escape"));
});

afterEach(async () => {
  await gateway?.stop();
  gateway = null;
  rmSync(home, { recursive: true, force: true });
  rmSync(outside, { recursive: true, force: true });
});

const paired = async () => {
  gateway = await startGateway(join(mkdtempSync(join(tmpdir(), "vitals-data-")), "remote"), home);
  const device = await pairDevice(gateway);
  return { gateway, ...device };
};

describe("fs: browse the Mac", () => {
  test("new devices can browse, roots are the shared folders, and listings sort and page", async () => {
    const { gateway: target, token, scopes } = await paired();
    expect(scopes).toContain("fsRead");
    const result = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const roots = yield* client["fs.roots"]({});
        const byName = yield* client["fs.list"]({ path: join(home, "Downloads"), sort: "name", hidden: false, offset: 0, limit: 500 });
        const byDate = yield* client["fs.list"]({ path: join(home, "Downloads"), sort: "date", hidden: false, offset: 0, limit: 2 });
        const hidden = yield* client["fs.list"]({ path: join(home, "Downloads"), sort: "name", hidden: true, offset: 0, limit: 500 });
        const nested = yield* client["fs.list"]({ path: join(home, "Downloads", "Trip"), sort: "name", hidden: false, offset: 0, limit: 500 });
        return { roots, byName, byDate, hidden, nested };
      }),
    );
    expect(result.roots.roots.map((root) => root.label)).toEqual(["Desktop", "Downloads"]);
    expect(result.byName.entries.map((entry) => entry.name)).toEqual(["Trip", "a.txt", "b.mov", "Escape", "file 9.txt", "file 10.txt"]);
    expect(result.byName.entries.find((entry) => entry.name === "Escape")?.kind).toBe("link");
    expect(result.byName.entries.find((entry) => entry.name === "b.mov")).toMatchObject({ kind: "file", size: 11, modifiedAt: 2_000_000 });
    expect(result.byName.parent).toBeNull();
    expect(result.byDate.total).toBe(6);
    expect(result.byDate.entries).toHaveLength(2);
    expect(result.byDate.entries[0]?.modifiedAt ?? 0).toBeGreaterThanOrEqual(result.byDate.entries[1]?.modifiedAt ?? 0);
    expect(result.hidden.total).toBe(7);
    expect(result.nested.parent).toBe(join(home, "Downloads"));
  });

  test("paths outside the shared folders, through links, and into secrets are refused", async () => {
    const { gateway: target, token } = await paired();
    const refusals = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const list = (path: string) => Effect.flip(client["fs.list"]({ path, sort: "name", hidden: false, offset: 0, limit: 10 }));
        return {
          outside: yield* list(outside),
          link: yield* list(join(home, "Downloads", "Escape")),
          home: yield* list(home),
          dotdot: yield* list(join(home, "Downloads", "..", "Library")),
        };
      }),
    );
    for (const refusal of Object.values(refusals)) expect(refusal).toMatchObject({ _tag: "CommandRejected" });

    target.app.emit({ t: "fsPolicy", access: "everything" });
    await Bun.sleep(50);
    const everything = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const roots = yield* client["fs.roots"]({});
        const homeList = yield* client["fs.list"]({ path: home, sort: "name", hidden: false, offset: 0, limit: 50 });
        const keychain = yield* Effect.flip(client["fs.list"]({ path: join(home, "Library", "Keychains"), sort: "name", hidden: false, offset: 0, limit: 10 }));
        const data = yield* Effect.flip(client["fs.list"]({ path: target.dataDir, sort: "name", hidden: false, offset: 0, limit: 10 }));
        return { roots, homeList, keychain, data };
      }),
    );
    expect(everything.roots.roots.map((root) => root.place)).toContain("disk");
    expect(everything.roots.roots[0]).toMatchObject({ place: "home", path: home });
    expect(everything.homeList.entries.map((entry) => entry.name)).toContain("Downloads");
    expect(everything.keychain).toMatchObject({ _tag: "CommandRejected" });
    expect(everything.data).toMatchObject({ _tag: "CommandRejected" });
  });

  test("getting a folder sends every file with its structure, byte-exact, and never follows links out", async () => {
    const { gateway: target, token, deviceId } = await paired();
    const result = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const offered = yield* client["fs.get"]({ paths: [join(home, "Downloads", "Trip"), join(home, "Downloads", "a.txt")] });
        const file = offered.drop.files.find((entry) => entry.name === "two.jpg");
        const response = yield* Effect.promise(() =>
          fetch(`${target.base}/api/drop/${offered.drop.id}/${file?.id ?? "x"}`, { headers: { authorization: `Drop ${offered.ticket.ticket}` } }),
        );
        const text = yield* Effect.promise(() => response.text());
        const whole = yield* client["fs.get"]({ paths: [join(home, "Downloads")] });
        return { offered, text, whole };
      }),
    );
    expect(result.offered.drop.state).toBe("running");
    expect(result.offered.drop.to).toMatchObject({ _tag: "Device", deviceId });
    expect(result.offered.drop.files.map((file) => [file.path, file.name]).sort()).toEqual([
      [null, "a.txt"],
      ["Trip", "one.jpg"],
      ["Trip/day 2", "two.jpg"],
    ]);
    expect(result.text).toBe("jpeg-two");
    expect(result.whole.drop.files.map((file) => file.name)).not.toContain("elsewhere.txt");
  });

  test("recent downloads are the newest files first, without folders, hidden files or anything outside", async () => {
    const { gateway: target, token } = await paired();
    const result = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const first = yield* client["fs.recent"]({ kind: "downloads", offset: 0, limit: 2 });
        const rest = yield* client["fs.recent"]({ kind: "downloads", offset: 2, limit: 2 });
        return { first, rest };
      }),
    );
    expect(result.first.entries.map((entry) => entry.name)).toEqual(["a.txt", "b.mov"]);
    expect(result.first.more).toBe(true);
    expect(result.rest.entries.map((entry) => entry.name)).toEqual(["file 9.txt", "file 10.txt"]);
    expect(result.rest.more).toBe(false);
  });
});

describe("fs: browse a phone", () => {
  test("a phone that serves its files can be browsed by another device, and goes away when it stops", async () => {
    gateway = await startGateway(join(mkdtempSync(join(tmpdir(), "vitals-data-")), "remote"), home);
    const target = gateway;
    const phone = await pairDevice(target);
    const other = await pairDevice(target);
    const phoneId = deviceIdOf(phone.deviceId);
    const roots = [{ label: "Downloads", path: "/storage/emulated/0/Download", place: "downloads" as const }];
    const listing = { path: "/storage/emulated/0/Download", parent: null, entries: [{ name: "a.jpg", path: "/storage/emulated/0/Download/a.jpg", kind: "file" as const, size: 3, modifiedAt: 1 }], total: 1 };

    const serving = withClient(target, phone.token, (client) =>
      client["fs.serve"]({ roots }).pipe(
        Stream.take(1),
        Stream.runForEach((request) => (request._tag === "List" ? client["fs.reply"]({ id: request.id, result: { _tag: "List", result: listing }, error: null }) : Effect.void)),
      ),
    );
    await Bun.sleep(300);
    const seen = await withClient(target, other.token, (client) =>
      Effect.gen(function* () {
        const devices = yield* client["fs.devices"]({});
        const phoneRoots = yield* client["fs.roots"]({ device: phoneId });
        const listed = yield* client["fs.list"]({ device: phoneId, path: "/storage/emulated/0/Download", sort: "name", hidden: false, offset: 0, limit: 50 });
        return { devices, phoneRoots, listed };
      }),
    );
    await serving;
    expect(seen.devices.devices).toContainEqual({ deviceId: phoneId, name: "Pixel 9", platform: "android", online: true, connected: true });
    expect(seen.devices.devices.map((device) => device.deviceId)).not.toContain(deviceIdOf(other.deviceId));
    expect(seen.phoneRoots.roots).toEqual(roots);
    expect(seen.listed).toEqual(listing);

    await Bun.sleep(200);
    const gone = await withClient(target, other.token, (client) => Effect.flip(client["fs.list"]({ device: phoneId, path: "/", sort: "name", hidden: false, offset: 0, limit: 10 })));
    expect(gone).toMatchObject({ _tag: "Unavailable" });
    expect(gone.message).toContain("isn't open");
  });
});

describe("fs: recent on a phone", () => {
  test("another device gets a phone's recent screenshots, and an older build says to update", async () => {
    gateway = await startGateway(join(mkdtempSync(join(tmpdir(), "vitals-data-")), "remote"), home);
    const target = gateway;
    const phone = await pairDevice(target);
    const old = await pairDevice(target);
    const other = await pairDevice(target);
    const phoneId = deviceIdOf(phone.deviceId);
    const roots = [{ label: "Pictures", path: "/storage/emulated/0/Pictures", place: "pictures" as const }];
    const shot = { name: "Screenshot_1.png", path: "/storage/emulated/0/Pictures/Screenshots/Screenshot_1.png", kind: "file" as const, size: 9, modifiedAt: 5 };

    const serving = withClient(target, phone.token, (client) =>
      client["fs.serve"]({ roots, recent: true }).pipe(
        Stream.take(1),
        Stream.runForEach((request) =>
          request._tag === "Recent" ? client["fs.reply"]({ id: request.id, result: { _tag: "Recent", result: { kind: request.kind, entries: [shot], more: false } }, error: null }) : Effect.void,
        ),
      ),
    );
    const oldServing = withClient(target, old.token, (client) => client["fs.serve"]({ roots }).pipe(Stream.take(1), Stream.runDrain, Effect.timeout("1500 millis"), Effect.ignore));
    await Bun.sleep(300);
    const seen = await withClient(target, other.token, (client) =>
      Effect.gen(function* () {
        const recent = yield* client["fs.recent"]({ device: phoneId, kind: "screenshots", offset: 0, limit: 30 });
        const stale = yield* Effect.flip(client["fs.recent"]({ device: deviceIdOf(old.deviceId), kind: "photos", offset: 0, limit: 30 }));
        return { recent, stale };
      }),
    );
    await serving;
    await oldServing;
    expect(seen.recent).toEqual({ kind: "screenshots", entries: [shot], more: false });
    expect(seen.stale).toMatchObject({ _tag: "CommandRejected" });
    expect(seen.stale.message).toContain("Update Vitals");
  });
});

describe("fs: transfer between devices", () => {
  test("Mac files go to another device as a drop to it, and never back to the Mac", async () => {
    const { gateway: target, token } = await paired();
    const other = await pairDevice(target);
    const otherId = deviceIdOf(other.deviceId);
    const result = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const sent = yield* client["fs.transfer"]({ paths: [join(home, "Downloads", "a.txt")], to: otherId });
        const toMac = yield* Effect.flip(client["fs.transfer"]({ paths: [join(home, "Downloads", "a.txt")], to: null }));
        return { sent, toMac };
      }),
    );
    expect(result.sent).toEqual({ files: 1 });
    expect(result.toMac).toMatchObject({ _tag: "CommandRejected" });
    const drops = await withClient(target, other.token, (client) =>
      client["drop.watch"]({}).pipe(
        Stream.take(1),
        Stream.runHead,
        Effect.map((event) => (event._tag === "Some" && event.value._tag === "Snapshot" ? event.value.drops : [])),
      ),
    );
    expect(drops.map((drop) => [drop.files.map((file) => file.name), drop.to])).toContainEqual([["a.txt"], { _tag: "Device", deviceId: otherId, name: "Pixel 9" }]);
  });

  test("a phone's files go to the Mac or a third device through the phone, not to itself", async () => {
    gateway = await startGateway(join(mkdtempSync(join(tmpdir(), "vitals-data-")), "remote"), home);
    const target = gateway;
    const phone = await pairDevice(target);
    const asker = await pairDevice(target);
    const third = await pairDevice(target);
    const phoneId = deviceIdOf(phone.deviceId);
    const relays: Array<string | null> = [];
    const serving = withClient(target, phone.token, (client) =>
      client["fs.serve"]({ roots: [{ label: "Download", path: "/storage/emulated/0/Download", place: "downloads" }], recent: true }).pipe(
        Stream.take(2),
        Stream.runForEach((request) => {
          if (request._tag !== "Send") return Effect.void;
          relays.push(request.relay);
          return client["fs.reply"]({ id: request.id, result: { _tag: "Send", files: request.paths.length }, error: null });
        }),
      ),
    );
    await Bun.sleep(300);
    const asked = await withClient(target, asker.token, (client) =>
      Effect.gen(function* () {
        const toMac = yield* client["fs.transfer"]({ device: phoneId, paths: ["/storage/emulated/0/Download/a.pdf"], to: null });
        const toThird = yield* client["fs.transfer"]({ device: phoneId, paths: ["/storage/emulated/0/Download/a.pdf"], to: deviceIdOf(third.deviceId) });
        const toItself = yield* Effect.flip(client["fs.transfer"]({ device: phoneId, paths: ["/storage/emulated/0/Download/a.pdf"], to: phoneId }));
        return { toMac, toThird, toItself };
      }),
    );
    await serving;
    expect(asked.toMac).toEqual({ files: 1 });
    expect(asked.toThird).toEqual({ files: 1 });
    expect(asked.toItself).toMatchObject({ _tag: "CommandRejected" });
    expect(relays).toEqual([null, third.deviceId]);
  });
});
