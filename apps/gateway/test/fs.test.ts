import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { DeviceId } from "@vitals/contracts";
import * as Effect from "effect/Effect";
import * as Schema from "effect/Schema";

import { type Gateway, adminOp, pairDevice, startGateway, withClient } from "./harness.ts";

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
    expect(result.roots.access).toBe("folders");
    expect(result.roots.writable).toBe(false);
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

  test("getting a folder sends every file with its structure, byte-exact", async () => {
    const { gateway: target, token, deviceId } = await paired();
    const result = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const offered = yield* client["fs.get"]({ paths: [join(home, "Downloads", "Trip"), join(home, "Downloads", "a.txt")] });
        const file = offered.drop.files.find((entry) => entry.name === "two.jpg");
        const response = yield* Effect.promise(() =>
          fetch(`${target.base}/api/drop/${offered.drop.id}/${file?.id ?? "x"}`, { headers: { authorization: `Drop ${offered.ticket.ticket}` } }),
        );
        const text = yield* Effect.promise(() => response.text());
        return { offered, text };
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
  });

  test("changing files needs its own permission and stays out of Library", async () => {
    const { gateway: target, token, deviceId } = await paired();
    const denied = await withClient(target, token, (client) => Effect.flip(client["fs.folder"]({ parent: join(home, "Downloads"), name: "New" })));
    expect(denied).toMatchObject({ _tag: "AuthError" });

    await adminOp(target.app, { _tag: "SetScopes", deviceId: deviceIdOf(deviceId), scopes: ["read", "operate", "files", "fsRead", "fsWrite"] });
    const allowed = await withClient(target, token, (client) =>
      Effect.gen(function* () {
        const made = yield* client["fs.folder"]({ parent: join(home, "Downloads"), name: "New" });
        const renamed = yield* client["fs.rename"]({ path: made.path, name: "Renamed" });
        const clash = yield* Effect.flip(client["fs.rename"]({ path: renamed.path, name: "a.txt" }));
        const root = yield* Effect.flip(client["fs.rename"]({ path: join(home, "Downloads"), name: "Gone" }));
        return { made, renamed, clash, root };
      }),
    );
    expect(allowed.made).toMatchObject({ name: "New", kind: "folder" });
    expect(allowed.renamed).toMatchObject({ name: "Renamed", path: join(home, "Downloads", "Renamed") });
    expect(allowed.clash).toMatchObject({ _tag: "CommandRejected" });
    expect(allowed.root).toMatchObject({ _tag: "CommandRejected" });
  });
});
