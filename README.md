# Vitals

Your Mac has a dashboard. Apple just hid it.

Vitals reads the temperature of your chip, the speed of your fans, and the health of your battery — straight from the hardware — and shows it in a window that looks like Apple built it. Free, open source, Apple Silicon only.

## Install

```sh
brew install --cask rafay99-epic/apps/vitals
```

Recommended — installs to `/Applications` and opens with **no macOS security prompt**. Vitals updates itself after that. Requires macOS 15+, Apple Silicon.

Living on the edge? The **Nightly channel** installs alongside Stable as a separate app (own icon + settings) and auto-updates from the newest pre-release:

```sh
brew install --cask rafay99-epic/apps/vitals-nightly
```

Prefer a direct download? Grab the **[.dmg](https://github.com/rafay99-epic/Vitals/releases/latest/download/Vitals.dmg)** — it isn't notarized (no paid Apple Developer account), so **right-click → Open** the first time to get past Gatekeeper. Homebrew is the smoother path.

## Monorepo layout

| App | Path | Stack |
| --- | --- | --- |
| Desktop app | [`apps/desktop`](apps/desktop) | Swift / SwiftUI (Swift Package Manager) |
| Marketing site | [`apps/marketing`](apps/marketing) | React + Vite + Tailwind |
| Remote gateway | [`apps/gateway`](apps/gateway) | Bun + Effect, compiled into the Mac app |
| Phone app | [`apps/mobile`](apps/mobile) | Expo (Android, iOS) + NativeWind |
| Web app | [`apps/web`](apps/web) | Expo web export, served by the gateway on your tailnet |
| Shared | [`packages/*`](packages) | contracts, client runtime, app screens, UI, Tailscale |

Tooling: [pnpm](https://pnpm.io) workspaces with a version catalog + [turbo](https://turborepo.com). Bun compiles and tests the gateway.

## Working in the repo

```sh
pnpm install              # once, at the root

pnpm build            # build everything
pnpm build:marketing    # just the site        (turbo build --filter=marketing)
pnpm build:desktop    # just the app         (turbo build --filter=desktop, macOS only)
pnpm dmg              # app + DMG installer  (turbo dmg --filter=desktop)
pnpm lint             # lint everything
pnpm test             # unit tests for both apps (swift test + bun test)
pnpm test:e2e         # browser checks against the built site
```

The website dev server: `cd apps/marketing && pnpm dev`.

For the **desktop app** (macOS, from `apps/desktop`):

```sh
swift build      # compile
swift test       # run the test suite
./dev.sh         # build + run "Vitals Dev" locally — your sandbox, never published
./nightly.sh     # build + run "Vitals Nightly" locally (the pre-release channel)
```

Desktop-app docs (architecture, sensors, fan control, release pipeline) live in [`apps/desktop/README.md`](apps/desktop/README.md).

## Release channels

Vitals ships in three channels that install **side by side** — separate apps, icons, settings, and data:

| Channel | Install | Source branch | Updates from |
| --- | --- | --- | --- |
| **Stable** | `brew install --cask rafay99-epic/apps/vitals` | `main` | the latest GitHub release |
| **Nightly** | `brew install --cask rafay99-epic/apps/vitals-nightly` | `nightly` | the newest pre-release |
| **Dev** | build locally — `./dev.sh` | any feature branch | — (no updater) |

- **`main` is Stable** — a curated release, cut by promoting `nightly → main` (squash) roughly weekly. Each push to `main` publishes a full GitHub Release (`Vitals.dmg`, version `0.<commit count>`), ordered by version.
- **`nightly` is the integration branch** — every merge auto-publishes a rolling `nightly` pre-release (`Vitals-Nightly.dmg`, ordered by CI build number) that Nightly users auto-update from.
- **Dev is local-only** — `./dev.sh` builds *Vitals Dev*; it is never published and has no updater. Break it all you like.

The casks come from the [`homebrew-apps`](https://github.com/rafay99-epic/homebrew-apps) tap; direct `.dmg` downloads are the fallback (`releases/latest/download/Vitals.dmg` for Stable, `releases/download/nightly/Vitals-Nightly.dmg` for Nightly).

## Contributing

1. **Branch from `nightly`** (`feat/…`, `fix/…`, `chore/…`) and open your **pull request against `nightly`**. The repo's default branch is `main` (Stable), so when you open the PR, **switch the base from `main` to `nightly`**. Draft while you iterate.
2. **`main` is protected — PRs or pushes straight to `main` are rejected.** Stable only moves via the maintainer's weekly `nightly → main` promotion, so don't target it.
3. Build and run your change locally with **`./dev.sh`** (installs *Vitals Dev* next to your real app — no release needed).
4. CI runs `swift test` + SwiftLint + a packaged build on every PR (the website and Convex have their own checks). A maintainer reviews and **squash-merges**; merging to `nightly` publishes a Nightly build automatically.

Full guide: **[CONTRIBUTING.md](CONTRIBUTING.md)**. Behavior standards: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Security reports: [SECURITY.md](SECURITY.md).

## License

Vitals is free software, licensed under the [GNU General Public License v3.0](LICENSE).
You may use, study, modify, and redistribute it under the same terms.

## Acknowledgements

The Applications & Cleanup feature is informed by **[Mole](https://github.com/tw93/mole)**
(GPL-3.0) — its battle-tested catalog of where macOS apps leave files behind, and its
safety-first uninstall design, shaped Vitals' native Swift implementation. Full credit
and thanks to the Mole project and its contributors.

---

© Syntax Lab Technology · Developed by [Abdul Rafay — rafay99.com](https://rafay99.com) · GPL-3.0
