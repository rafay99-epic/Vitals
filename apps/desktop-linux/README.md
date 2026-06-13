# Vitals for Linux

A native **Swift + GTK4/libadwaita** port of [Vitals](../desktop), focused on
**monitoring only** — the Dashboard and a menu-bar/tray item. Cleanup,
uninstall, and application management stay exclusive to the macOS build by
design.

This is a separate app from the macOS one: its own package, its own build, its
own CI. It ships **no auto-updater**.

## Status

Feature-complete for v1:

- ✅ Sensor services (`/sys`, `/proc`) — temps, fans, CPU, memory + PSI, battery, processes
- ✅ Model + rolling history
- ✅ Dashboard UI (stat tiles, Cairo sparklines, breakdown cards)
- ✅ Tray (StatusNotifierItem with a live-readings tooltip + click-to-open)
- ✅ AppImage packaging in CI

The tray's right-click menu (the `com.canonical.dbusmenu` layout protocol) is a
planned follow-up; for now the tray shows the live readings on hover and opens
the window on click. The D-Bus tray path is compile-verified in CI and needs a
real desktop session to confirm runtime behaviour.

## Download & run

Each CI run builds **both architectures** and uploads them as separate workflow
artifacts (no install, no GitHub Release):

- **`Vitals-linux-x86_64-AppImage`** — Intel/AMD desktops and laptops.
- **`Vitals-linux-aarch64-AppImage`** — ARM (Raspberry Pi, ARM VMs, Asahi, etc.).

Pick the one matching `uname -m` on the target machine — an x86_64 AppImage will
**not** run on ARM and vice versa (the CPU can't execute a foreign-arch binary).
Download from the run's *Artifacts* section, then:

```sh
chmod +x Vitals-*.AppImage
./Vitals-*.AppImage
```

Needs a GitHub account with read access to the repo to download; files are kept
for 90 days.

## Architecture

Mirrors the macOS layering — services read hardware and know nothing about UI;
the model samples off the main thread and publishes; views only display.

- **`Sources/VitalsCore`** — pure Foundation. Reads `/sys` and `/proc`, parses
  readings. No GTK, so it builds and unit-tests on **any** platform (including a
  macOS dev box) via `swift test`.
- **`Sources/Vitals`** — the GTK executable. Uses
  [Adwaita for Swift](https://git.aparoksha.dev/aparoksha/adwaita-swift) for a
  declarative, SwiftUI-like GNOME UI, and Cairo (`CCairo`) to render charts.
- **`Sources/CCairo`** — system-library shim for Cairo. Adwaita's `Picture`
  decodes raster data only, so sparklines are drawn to PNG with Cairo and handed
  over as bytes.

## Honesty

Every number is a real reading. Hardware that exposes no fan, no battery, or no
sensor shows "N/A" / "Fanless" / hidden — never `0` and never a fabricated
value. Fans are **read-only**; this app never writes to hardware.

## Building

Needs a Linux toolchain with `gtk4`, `libadwaita`, and `cairo` dev packages. The
included `Dockerfile` captures exactly that (and matches CI):

```sh
docker build -t vitals-linux apps/desktop-linux
docker run --rm -v "$PWD":/src -w /src/apps/desktop-linux vitals-linux ./build.sh
```

Or directly on a Linux box with the dev packages installed:

```sh
swift test          # VitalsCore parser tests (also runs on macOS)
./build.sh          # release binary → build/Vitals
```

## Desktop integration notes

The tray item (Phase 4) uses the `StatusNotifierItem` D-Bus protocol — supported
natively by KDE and most desktops. **GNOME Shell needs the
[AppIndicator extension](https://extensions.gnome.org/extension/615/appindicator-support/)**
installed for the icon to appear.

## License & credit

GPL-3.0 (see the repository [`LICENSE`](../../LICENSE)). Vitals is by
Syntax Lab Technology / Abdul Rafay ([rafay99.com](https://rafay99.com)).
