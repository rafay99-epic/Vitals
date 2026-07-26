# Vitals project memory

This file records durable project context for Codex work. `AGENTS.md` remains the
authoritative instruction file; this document captures the current maintenance
thread and user preferences so future sessions can resume without rediscovery.

## Working workflow

- Always start feature work from the local `nightly` branch.
- Create a dedicated `codex/...` feature branch from `nightly`.
- Never modify `nightly` or `main` directly.
- Push the feature branch and open a draft PR when the implementation is ready.
- The user squash-merges PRs.
- Test desktop changes with `apps/desktop/dev.sh`, which installs `Vitals Dev.app`.
- Never overwrite, quit, or relaunch Stable at `/Applications/Vitals.app`.
- Plans must be authored as HTML, published through PagePilot MCP, and returned
  with the PagePilot URL and delete key/ID.

## Current maintenance thread: memory, fan persistence, and OS compatibility

The user reports long-run Vitals memory usage reaching roughly 800 MB and a fan
control error in Overview when setting a fan to maximum:

> Couldn't save fan settings: The folder “fan-state.json” doesn't exist.

The initial audit found:

- Stable was approximately 108 MB resident during a single live snapshot, so the
  800 MB report still needs a long-run reproduction rather than being called a
  confirmed leak.
- `ContentView` keeps every visited section mounted with opacity. This retains
  SwiftUI view trees, charts, and state after navigation.
- `CleanupModel`, `StorageModel`, and `AppsModel` can retain large scan results
  for the life of the main window.
- `VitalsModel` starts a watchdog that cancels a sampling `Task`; the underlying
  synchronous hardware operation may continue, so a wedged sample can allow
  overlapping/queued work over time.
- `FanController.refreshInstalled()` checks only the launchd plist. `FanControl`
  writes to `/Library/Application Support/<channel>/fan-state.json` but assumes
  its parent directory still exists. A stale plist plus a missing support folder
  matches the reported error.
- The desktop package targets macOS 15.0. Liquid Glass is conditionally gated for
  macOS 26, with classic rendering intended as the older-OS fallback.

## Planned implementation order

1. Add memory diagnostics and reproduce memory slope with Instruments/Memory Graph.
2. Reduce SwiftUI retention by mounting only the active section while preserving
   long-running model tasks where required.
3. Make sensor sampling strictly serial and cancellation-safe; reduce unnecessary
   process/GPU/power sampling and coalesce publications.
4. Add fan helper health checks and a privileged repair path for missing support
   directories/state files, with regression tests.
5. Validate on macOS 15 and macOS 26+ using the appropriate Xcode/SDK lanes, then
   verify the Dev build visually and with a long-run soak test.

## Work started on `codex/memory-fan-macos-compat`

- Fan state writes now create their parent directory when permissions allow.
- A registered helper with a missing support directory is surfaced as repairable;
  the Overview card offers `Repair Fan Control`.
- Helper installation no longer swallows failure while seeding the state file.
- The main window now mounts only the selected section. Long-lived models remain
  owned by `ContentView`, while process and per-app energy timers stop when their
  views disappear.
- `VitalsModel` now keeps one in-flight sample, treats synchronous sensor work as
  non-interruptible, and never releases the sampling slot from the watchdog. This
  prevents a wedged IOKit call from accumulating overlapping tasks. Process/GPU/
  power reads are demand-driven by the selected section, menu bar, widgets, and
  alerts.
- `StorageModel`'s path-size cache is capped at 50,000 entries; it remains a
  regenerable acceleration cache rather than an unbounded window-lifetime map.
- Diagnostic snapshots now include a point-in-time Vitals resident/virtual
  footprint for long-run memory investigations without adding per-tick publisher
  churn.
- Changed sources pass `swiftc -parse` and `git diff --check`. Full `swift test`
  and `./dev.sh` currently stop before linking because this host has Command Line
  Tools without the SwiftUI macro plugin (`SwiftUIMacros.StateMacro`); validation
  still needs full Xcode on macOS 15 and macOS 26 lanes.

## Evidence locations

- `apps/desktop/Sources/Vitals/Views/ContentView.swift`
- `apps/desktop/Sources/Vitals/Models/VitalsModel.swift`
- `apps/desktop/Sources/Vitals/Services/FanController.swift`
- `apps/desktop/Sources/Vitals/Services/FanDaemon.swift`
- `apps/desktop/Sources/Vitals/Services/DataHome.swift`
- `apps/desktop/Package.swift`
