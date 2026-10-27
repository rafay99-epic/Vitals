import { describe, expect, test } from "bun:test";
import { type Connection, type ConnectionState, type VitalsClient, Store } from "@vitals/client-runtime";
import type { FsEntry } from "@vitals/contracts";
import * as Effect from "effect/Effect";

import { hasPreview, MacFiles } from "../src/state/files.ts";

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

  test("previews are offered for images, video and documents, never folders", () => {
    expect(hasPreview(entry("clip.mov"))).toBe(true);
    expect(hasPreview(entry("plan.pdf"))).toBe(true);
    expect(hasPreview(entry("archive.zip"))).toBe(false);
    expect(hasPreview({ ...entry("Photos.jpg"), kind: "folder" })).toBe(false);
  });
});
