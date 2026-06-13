# Vitals for Linux

A native **Swift + GTK4/libadwaita** port of [Vitals](../desktop), focused on
**monitoring only** — the Dashboard and a menu-bar/tray item. Cleanup,
uninstall, and application management stay exclusive to the macOS build by
design.

This is a separate app from the macOS one: its own package, its own build, its
own CI. It ships **no auto-updater**.

## Status

Built in phases, each landing as its own PR:

- **Phase 0 — scaffold + build loop + charts spike + CI** ← current
- Phase 1 — sensor services (`/sys`, `/proc`)
- Phase 2 — model + off-thread sampling
- Phase 3 — dashboard UI
- Phase 4 — tray (StatusNotifierItem)
- Phase 5 — AppImage packaging

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
