import { describe, expect, test } from "bun:test";

import { downloadsNow, notesOf, type PlayState, sheetFor, tidyNotes, type UpdateState, updateView } from "../src/lib/updateModel.ts";

const ready: UpdateState = { _tag: "Ready", id: "u1", notes: "Faster files." };
const current: UpdateState = { _tag: "Current", at: 0 };
const noPlay: PlayState = { _tag: "Off", reason: "dev" };

describe("updates", () => {
  test("notes read as a sentence without the commit prefix", () => {
    expect(tidyNotes("fix(mobile): sheet grid starts at the top")).toBe("Sheet grid starts at the top.");
    expect(tidyNotes("Swipe between files!")).toBe("Swipe between files!");
    expect(notesOf({ extra: { expoClient: { extra: { updateNotes: "feat: zip previews" } } } })).toBe("Zip previews.");
    expect(notesOf({ extra: {} })).toBe("");
  });

  test("Wi-Fi only waits on cellular; ask first never downloads by itself", () => {
    expect(downloadsNow("wifi", "cellular")).toBe(false);
    expect(downloadsNow("wifi", "other")).toBe(true);
    expect(downloadsNow("any", "cellular")).toBe(true);
    expect(downloadsNow("ask", "wifi")).toBe(false);
  });

  test("a finished Play download outranks a ready quick update", () => {
    expect(updateView(ready, { _tag: "Downloaded", version: 240 }, false).kind).toBe("play-ready");
    expect(updateView(ready, noPlay, false).kind).toBe("ready");
    expect(updateView(current, noPlay, true).kind).toBe("rolled-back");
    expect(updateView({ _tag: "Off" }, noPlay, false).kind).toBe("off");
  });

  test("sheets wait for the app to open, show once, and respect Later on a Play version", () => {
    const base = { quick: ready, play: noPlay, skippedPlay: null };
    expect(sheetFor({ ...base, fresh: false, shown: new Set() })).toBeNull();
    expect(sheetFor({ ...base, fresh: true, shown: new Set() })?.kind).toBe("ready");
    expect(sheetFor({ ...base, fresh: true, shown: new Set(["ready:u1"]) })).toBeNull();
    const play: PlayState = { _tag: "Available", version: 240 };
    expect(sheetFor({ quick: current, play, fresh: true, shown: new Set(), skippedPlay: 240 })).toBeNull();
    expect(sheetFor({ quick: current, play: { _tag: "Downloaded", version: 240 }, fresh: false, shown: new Set(), skippedPlay: null })?.kind).toBe("play-ready");
  });
});
