import { describe, expect, test } from "bun:test";
import { type Connection, type ConnectionState, Store } from "@vitals/client-runtime";
import { Clip } from "@vitals/contracts";
import * as Schema from "effect/Schema";

import { MacClips, sentFolder } from "../src/state/clips.ts";

const clip = (id: string, at: number): Clip =>
  Schema.decodeUnknownSync(Clip)({ id, kind: "text", at, deviceId: null, source: "Safari", text: id, truncated: false, name: null, mime: null, bytes: 0, files: null, thumb: null, pinned: false });

const idle = (): Connection => ({
  state: new Store<ConnectionState>({ _tag: "Idle" }),
  call: () => new Promise(() => {}),
  watch: () => () => {},
  wake: () => {},
  suspend: () => {},
  dispose: () => {},
});

describe("MacClips", () => {
  test("keeps history newest first and tells listeners only about new copies", () => {
    const clips = new MacClips(idle(), () => {});
    const heard: Array<string> = [];
    clips.onAdded((added) => heard.push(added.id));
    clips.apply({ _tag: "Snapshot", enabled: true, keepDays: 7, clips: [clip("clip-old-1", 1), clip("clip-new-1", 5)] });
    clips.apply({ _tag: "Added", clip: clip("clip-new-2", 9) });
    clips.apply({ _tag: "Removed", ids: [clip("clip-old-1", 1).id] });
    expect(clips.clips.get().map((item) => item.id)).toEqual(["clip-new-2", "clip-new-1"]);
    expect(heard).toEqual(["clip-new-2"]);
    clips.dispose();
  });

  test("a removed clip stays hidden through a snapshot and comes back on Undo", () => {
    const clips = new MacClips(idle(), () => {});
    const first = clip("clip-one-1", 1);
    clips.apply({ _tag: "Snapshot", enabled: true, keepDays: 7, clips: [first] });
    const undo = clips.remove(first);
    clips.apply({ _tag: "Snapshot", enabled: true, keepDays: 7, clips: [first] });
    expect(clips.clips.get()).toEqual([]);
    undo();
    expect(clips.clips.get()).toEqual([first]);
    clips.dispose();
  });

  test("copying the same thing again on the Mac counts as a new copy", () => {
    const clips = new MacClips(idle(), () => {});
    const seen: Array<number> = [];
    clips.onAdded((copy) => seen.push(copy.at));
    const first = clip("clip-again-1", 1);
    clips.apply({ _tag: "Snapshot", enabled: true, keepDays: 7, clips: [first] });
    clips.apply({ _tag: "Updated", clip: { ...first, pinned: true } });
    clips.apply({ _tag: "Updated", clip: { ...first, at: 9 } });
    expect(seen).toEqual([9]);
    clips.dispose();
  });

  test("a batch of files for Downloads gets a Finder-safe folder name", () => {
    expect(sentFolder(new Date(2026, 9, 4, 7, 5))).toBe("Sent 2026-10-04 at 07.05");
  });

  test("the snapshot carries how long the Mac keeps history", () => {
    const clips = new MacClips(idle(), () => {});
    clips.apply({ _tag: "Snapshot", enabled: true, keepDays: 30, clips: [] });
    expect(clips.keepDays.get()).toBe(30);
    clips.dispose();
  });
});
