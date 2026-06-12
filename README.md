# Vitals

Your Mac has a dashboard. Apple just hid it.

Vitals reads the temperature of your chip, the speed of your fans, and the health of your battery — straight from the hardware — and shows it in a window that looks like Apple built it. Free, open source, Apple Silicon only.

**[Download the latest release](https://github.com/rafay99-epic/Vitals/releases/latest/download/Vitals.dmg)** · requires macOS 15+

## Monorepo layout

| App | Path | Stack |
| --- | --- | --- |
| Desktop app | [`apps/desktop`](apps/desktop) | Swift / SwiftUI (Swift Package Manager) |
| Website | [`apps/website`](apps/website) | React + Vite + Tailwind |

Tooling: [bun](https://bun.sh) workspaces + [turbo](https://turborepo.com) for task orchestration.

## Working in the repo

```sh
bun install              # once, at the root

bun run build            # build everything
bun run build:website    # just the site        (turbo build --filter=website)
bun run build:desktop    # just the app         (turbo build --filter=desktop, macOS only)
bun run dmg              # app + DMG installer  (turbo dmg --filter=desktop)
bun run lint             # lint everything
```

The website dev server: `cd apps/website && bun run dev`.

Desktop-app docs (architecture, sensors, fan control, release pipeline) live in [`apps/desktop/README.md`](apps/desktop/README.md).

## CI / releases

- `CI` and `Release` workflows run on `apps/desktop/**` changes; every app change on `main` publishes a GitHub Release (version = commit count) with the DMG.
- `Website` workflow runs on `apps/website/**` changes (bun + turbo on Ubuntu).
- The website's download button always serves the newest DMG via `releases/latest/download/Vitals.dmg`.

---

© Syntax Lab Technology · Developed by [Abdul Rafay — rafay99.com](https://rafay99.com)
