import { describe, expect, test } from "bun:test";
import { type Connection, type ConnectionState, type VitalsClient, Store } from "@vitals/client-runtime";
import { DeviceId, type FsDevice, type FsEntry } from "@vitals/contracts";
import * as Effect from "effect/Effect";
import * as Schema from "effect/Schema";

import { destinationsFor, hasPreview, MacFiles, mergeNewest, thumbKey } from "../src/state/files.ts";

const deviceIdOf = Schema.decodeUnknownSync(DeviceId);

const entry = (name: string): FsEntry => ({ name, path: `/Users/me/Downloads/${name}`, kind: "file", size: 1, modifiedAt: 0 });

const thumbsConnection = (batches: Array<ReadonlyArray<string>>): Connection => {
  const client = {
    "fs.thumbs": ({ paths }: { readonly paths: ReadonlyArray<string> }) => {
      batches.push(paths);
      return Effect.succeed({ thumbs: paths.map((path) => ({ path, jpeg: path.endsWith(".jpg") ? "AAAA" : null })) });
    },
  };
  return {
    state: new Store<ConnectionState>({ _tag: "Idle" }),
    call: async (run) => ({ ok: true, value: await Effect.runPromise(run(client as unknown as VitalsClient) as Effect.Effect<never>) }),
    watch: () => () => {},
    wake: () => {},
    suspend: () => {},
    dispose: () => {},
  };
};

const settle = () => new Promise((resolve) => setTimeout(resolve, 150));

describe("MacFiles thumbnails", () => {
  test("asks once per path, in batches the Mac accepts, and only for files with a preview", async () => {
    const batches: Array<ReadonlyArray<string>> = [];
    const files = new MacFiles(thumbsConnection(batches));
    const photos = Array.from({ length: 30 }, (_, index) => entry(`IMG_${String(index)}.jpg`));
    files.want([...photos, entry("notes.bin"), { ...entry("Trip"), kind: "folder" }]);
    files.want(photos.slice(0, 5));
    await settle();
    expect(batches.map((batch) => batch.length)).toEqual([24, 6]);
    expect(batches.flat()).not.toContain("/Users/me/Downloads/notes.bin");
    expect(files.thumbs.get().get(photos[0]?.path ?? "")).toBe("data:image/jpeg;base64,AAAA");

    files.want(photos);
    await settle();
    expect(batches).toHaveLength(2);
    files.dispose();
  });

  test("a phone's thumbnails are kept apart from the Mac's, even for the same path", async () => {
    const batches: Array<ReadonlyArray<string>> = [];
    const files = new MacFiles(thumbsConnection(batches));
    const photo = entry("IMG_1.jpg");
    const phone = deviceIdOf("01a17bf6-b432-736b-a51e-2b2972ac7818");
    files.want([photo]);
    await settle();
    files.want([photo], phone);
    await settle();
    expect(batches).toHaveLength(2);
    expect(files.thumbs.get().has(thumbKey(photo.path, phone))).toBe(true);
    expect(thumbKey(photo.path, phone)).not.toBe(thumbKey(photo.path));
    files.dispose();
  });

  test("previews are offered for images, video and documents, never folders", () => {
    expect(hasPreview(entry("clip.mov"))).toBe(true);
    expect(hasPreview(entry("plan.pdf"))).toBe(true);
    expect(hasPreview(entry("archive.zip"))).toBe(false);
    expect(hasPreview({ ...entry("Photos.jpg"), kind: "folder" })).toBe(false);
  });
});

describe("Transfer destinations", () => {
  const me = deviceIdOf("01a17bf6-b432-736b-a51e-2b2972ac7801");
  const iphone = deviceIdOf("01a17bf6-b432-736b-a51e-2b2972ac7802");
  const tablet = deviceIdOf("01a17bf6-b432-736b-a51e-2b2972ac7803");
  const phone = (deviceId: DeviceId): FsDevice => ({ deviceId, name: deviceId, platform: "ios", online: true });
  const phones = [phone(iphone), phone(tablet)];
  const where = (from: DeviceId | null) => destinationsFor(from, me, phones).map((to) => (to._tag === "Phone" ? to.device.deviceId : to._tag));

  test("never offers the device the files are on", () => {
    expect(where(null)).toEqual(["Here", iphone, tablet]);
    expect(where(iphone)).toEqual(["Here", "Mac", tablet]);
    expect(where(me)).toEqual(["Mac", iphone, tablet]);
  });
});

describe("mergeNewest", () => {
  const at = (name: string, modifiedAt: number): FsEntry => ({ ...entry(name), modifiedAt });

  test("merges kinds newest first and stops where an unfinished page stops", () => {
    const shots = { entries: [at("s1", 90), at("s2", 50)], more: true };
    const photos = { entries: [at("p1", 80), at("p2", 40), at("p3", 10)], more: false };
    const merged = mergeNewest([shots, photos]);
    expect(merged.entries.map((item) => item.name)).toEqual(["s1", "p1", "s2"]);
    expect([...merged.behind]).toEqual([0]);
    expect(mergeNewest([{ ...shots, more: false }, photos]).entries).toHaveLength(5);
    expect(mergeNewest([shots, { entries: [at("s1", 90)], more: false }]).entries.map((item) => item.name)).toEqual(["s1", "s2"]);
  });
});
