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
- **Memory** — Activity Monitor's full breakdown (app / wired / compressed /
  cached / free) as a stacked bar, swap usage, the kernel memory-pressure
  level (green/yellow/red), and a memory + swap history chart
- **Battery health** — charge, Maximum Capacity, cycle count, charge/discharge
  wattage, time remaining
- **History log** — readings appended to
  `~/Library/Application Support/Vitals/history.csv` every 10 s (rotates at
  50 MB); export or reveal it from Settings → Logging

## Releases and updates

Every push to `main` triggers the Release workflow: it builds the app,
stamps the version, packages the DMG, and publishes a GitHub release with
the DMG attached. The version is `0.<total commit count>` — 10 commits on
`main` means `0.10`.

The app keeps itself current:

- **Automatic** — with "Check for updates automatically" on (Settings →
  Updates, default), Vitals checks at launch and every 6 hours. When a newer
  release exists you get a notification and a banner in the dashboard.
- **Manual** — turn the toggle off and use **Check for Updates** in Settings
  whenever you like.

Either way, **Install Update** downloads the release DMG, installs it to
`/Applications/Vitals.app`, and relaunches the new version.

The repository is public, so update checks need no authentication. (If it
is ever made private again, the app falls back to the local GitHub CLI
login — `gh auth login` — and no tokens are stored in the app.)

## Settings (⌘, or the gear in the toolbar)

- **Readings** — temperature unit (°C/°F), refresh rate (1/2/5 s), chart
  history window (5/10/30 min)
- **Appearance** — theme (System/Light/Dark) and Liquid Glass (translucent
  window and glass cards on macOS 26)
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

The app is ad-hoc signed by default, so it runs on the machine that built it. To
use it on another Mac, build it there (or sign with your own Developer ID).

### Stable signing (so permissions survive updates)

Ad-hoc signatures change every build, and macOS keys TCC grants (Accessibility /
Microphone / Screen Recording) and Gatekeeper identity to the signature — so each
ad-hoc update looks like a brand-new app and silently drops every permission. To
keep grants across updates, sign every build with one **stable self-signed
certificate** (no Apple account, no notarization). Generate it once:

```sh
./Scripts/make-signing-cert.sh        # creates "Vitals Local Signing", imports it,
                                       # prints the two CI-secret values
CODESIGN_IDENTITY="Vitals Local Signing" ./build.sh   # signs locally with it
```

`build.sh` reads `CODESIGN_IDENTITY`; unset (or a name not in the keychain) falls
back to ad-hoc. In CI the cert is imported from secrets on the release/nightly
jobs only — see the repo CLAUDE.md "Code signing" section. The **same** cert /
`.p12` can be reused across every app in this family.

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

## Project layout

```
Sources/
  PrivateSensors/        C shim exposing the private IOKit/SMC symbols
  Vitals/
    App/                 entry point, CLI tools, App scene, menu bar
    Models/              VitalsModel — the polling view-model
    Services/            one file per data source:
                           SMC, HIDSensors, SystemStats, ProcessSampler,
                           Battery, HistoryLogger, Notifications, FanController
    Settings/            AppSettings (persistence) + SettingsView
    Updates/             Updater — GitHub release checks, download, install
    Views/               ContentView, Components, and the dashboard cards
Scripts/                 icon and DMG-background renderers
Resources/               Info.plist, app icon
.github/workflows/       ci.yml (build/lint), release.yml (build + publish)
build.sh / make-dmg.sh   build the app and the installer
```

The rule of thumb: a **Service** talks to the hardware/OS and knows nothing
about SwiftUI; the **Model** polls services on a timer and publishes state;
**Views** only read the model and settings. New data sources slot into
`Services/` and surface through `VitalsModel`.

## Fan control

Click **Enable Fan Control** in the Fans card (one administrator prompt).
After that, the slider and presets — in the window *and* the menu-bar panel —
change fan speed with no further prompts; **Disable…** removes the helper.

How it works:

- A small **LaunchDaemon** (`com.tudotechlab.vitals.fand`) runs the app's own
  binary as root (`Vitals --fan-daemon`). The GUI writes the desired state to
  `/Library/Application Support/Vitals/fan-state.json`; the daemon applies it.
  This is why there's only one password — installing the helper — instead of
  one per change.
- **Apple Silicon SMC unlock**: M3/M4 firmware holds fans in "system mode"
  (`F0Md` reads `3`) and rejects a direct manual-mode write. The daemon sets
  the diagnostic key `Ftst = 1`, waits for the mode write to take, then sets
  the target rpm `F0Tg` (a float on Apple Silicon, not the Intel `fpe2`
  format). The unlock is re-applied on a loop so manual speed survives
  sleep/wake. Mechanism documented by
  [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan).
- macOS thermal management still runs underneath as a safety net, and speeds
  are clamped to each fan's rated range. Fanless Macs show a passive-cooling
  message instead.

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
