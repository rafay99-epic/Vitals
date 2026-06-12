# Vitals

A native macOS system monitor for Apple Silicon. Live CPU die temperatures,
fan speed, CPU usage, memory, and thermal pressure — in a window with charts
and as a temperature readout in the menu bar.

## Features

- Live CPU die temperatures (per-sensor bar chart + history line chart with
  hover tooltips), fan rpm, CPU usage, memory, thermal pressure
- **Alerts** — a notification when the average CPU stays above your threshold
  for 2 minutes (10-minute cooldown), and when macOS escalates thermal
  pressure to Serious/Critical
- **Top processes** — the 5 biggest CPU consumers right now (100% = one core)
- **Battery health** — charge, Maximum Capacity, cycle count, charge/discharge
  wattage, time remaining
- **History log** — readings appended to
  `~/Library/Application Support/Vitals/history.csv` every 10 s (rotates at
  50 MB); export or reveal it from Settings → Logging

## Releases and updates

Every push to `main` triggers the Release workflow: it builds the app,
stamps the version (`VERSION` file + build number, e.g. `1.1.42`), packages
the DMG, and publishes a GitHub release with the DMG attached.

The app keeps itself current:

- **Automatic** — with "Check for updates automatically" on (Settings →
  Updates, default), Vitals checks at launch and every 6 hours. When a newer
  release exists you get a notification and a banner in the dashboard.
- **Manual** — turn the toggle off and use **Check for Updates** in Settings
  whenever you like.

Either way, **Install Update** downloads the release DMG, installs it to
`/Applications/Vitals.app`, and relaunches the new version.

Because the repository is private, update checks authenticate using your
GitHub CLI login (`gh auth login`) — no tokens are stored in the app. To
bump the marketing version, edit the `VERSION` file.

## Settings (⌘, or the gear in the toolbar)

- **Readings** — temperature unit (°C/°F), refresh rate (1/2/5 s), chart
  history window (5/10/30 min)
- **Menu bar** — show/hide the menu bar item, choose what it displays
  (average temp, hottest core, fan rpm, icon only), and set the warning
  threshold at which the icon turns into a flame
- **Application** — launch at login, hide the Dock icon to run Vitals as a
  menu-bar-only app

Preferences persist across launches via `UserDefaults`.

## Install

Requirements: an Apple Silicon Mac on macOS 15 or newer, with Xcode 16+
installed (for the Swift toolchain).

```sh
git clone https://github.com/rafay99-epic/Vitals.git
cd Vitals
./build.sh
```

The script compiles with SwiftPM, assembles `build/Vitals.app`, renders the
icon, and ad-hoc signs the bundle.

### Option A — DMG installer (recommended)

```sh
./make-dmg.sh
open build/Vitals.dmg
```

A disk image mounts with the familiar installer window — drag **Vitals** onto
the **Applications** folder, eject the disk, and launch Vitals from
Applications or Spotlight. (CI also builds this DMG on every push; grab it
from the workflow run's artifacts.)

### Option B — run straight from the build folder

```sh
open build/Vitals.app                  # run in place, or
cp -R build/Vitals.app /Applications/  # install manually
```

Two prompts to expect on first launch: macOS asks to allow notifications
(needed for the overheat alerts), and if you enable "Launch at login" in
Settings, Vitals appears under System Settings → General → Login Items.

The app is ad-hoc signed, so it runs on the machine that built it. To use it
on another Mac, build it there (or sign with your own Developer ID).

## Rebuild after changes

```sh
./build.sh
```

Delete `Resources/AppIcon.icns` first if you want the icon re-rendered.

## Sanity-check the sensors without the GUI

```sh
.build/release/Vitals --probe
```

Prints every temperature sensor, fan, and memory reading once and exits.

## How it works

- **Temperatures** — Apple Silicon exposes named temperature sensors through
  the IOKit HID event system (`PMU tdie*` = CPU die banks, `NAND` = SSD,
  `gas gauge battery` = battery). Reading the event values uses two
  long-stable private IOKit functions, declared in
  `Sources/PrivateSensors/include/PrivateSensors.h`.
- **Fans** — read from the SMC (`AppleSMC` kernel service) via
  `IOConnectCallStructMethod`: key `FNum` for the count, `F0Ac/Mn/Mx/Tg` for
  actual/min/max/target rpm. Fans stopping completely at idle is normal on
  M-series MacBook Pros.
- **CPU usage** — `host_processor_info` tick deltas between samples.
- **Memory** — `host_statistics64`, counted the way Activity Monitor does
  (app memory + wired + compressed).
- **UI** — SwiftUI + Swift Charts, polling every 2 s, keeping 10 minutes of
  history. The menu bar extra shows the rounded average CPU temperature.

No sandbox (SMC/HID access requires it off), no network, read-only — it never
writes to the SMC.
