# Contributing to Vitals

Thanks for your interest in Vitals — a native macOS hardware monitor and app
manager. Contributions of all kinds are welcome: bug reports, fixes, features,
docs, and design feedback. This guide explains how to get set up and how changes
land.

By participating you agree to our [Code of Conduct](./CODE_OF_CONDUCT.md).

## License

Vitals is **GPL-3.0** (see [`LICENSE`](./LICENSE)). By contributing, you agree
that your contributions are licensed under GPL-3.0 (inbound = outbound). Don't
paste code from incompatible licenses. The **Mole** project
(github.com/tw93/mole) credit must remain wherever it currently appears (README,
`LeftoverScanner.swift`, the website, and the app's About) — functionality was
informed by Mole; no code was copied.

## Project layout

This is a **bun + turbo monorepo**:

- `apps/desktop` — the macOS app (Swift / SwiftUI, SwiftPM).
- `apps/website` — the marketing site (React + Vite + Tailwind v4, TanStack Router).
- `convex/` — a deliberately thin Convex backend (live GitHub proxy; no database).

## Getting set up

```sh
bun install                  # once, from the repo root
bun run dev                  # website (vite) + convex dev together
bun run build / lint / test  # everything, via turbo
```

For the **desktop app** (from `apps/desktop`, requires macOS):

```sh
swift build        # compile
swift test         # run the test suite
./dev.sh           # build + install "Vitals Dev" side by side with a Stable install
```

`./dev.sh` builds a separate **Vitals Dev** app (own bundle id, icon, and
settings) so you can test without touching a real install.

## Branch & PR workflow

Vitals runs three channels: **Stable** (`main`), **Nightly** (the `nightly`
integration branch, published as an auto-updating pre-release for testers), and
**Dev** (your local `./dev.sh` build — never published).

- **Branch from `nightly`, and open your PR against `nightly`** (`fix/...`,
  `feat/...`, `chore/...`). That's the integration line — `nightly` is the
  default branch, so new PRs target it automatically. Opening the PR as a
  **draft** while you iterate is encouraged.
- **Never commit directly to `main`.** `main` is Stable: the maintainer promotes
  `nightly → main` (squash) on a weekly cadence, and that push cuts the Stable
  release. Direct pushes to `main` are blocked.
- Use `./dev.sh` to build and run your change locally as **Vitals Dev** while you
  work — no release needed. Once your PR merges to `nightly`, CI publishes a
  Nightly build automatically.
- Keep a PR focused on one thing. Update docs when behavior changes.
- The maintainer **squash-merges** PRs, so your branch's individual commits are
  collapsed — a clear PR title and description matter most.

### What runs on your PR

- **CI** (`swift test` + SwiftLint + a release build that packages the DMG) must
  be green. The release pipeline is gated on these — a red check never ships.
- **CodeRabbit** posts an automated review. Please address or reply to its
  findings; project-specific rules are encoded in `.coderabbit.yaml`.

### Commit messages

Match the existing style: a short, imperative, area-prefixed subject
(e.g. `tests: isolate UserDefaults per test`, `website: fix mobile overflow`),
with a body explaining the *why* when it isn't obvious.

## Principles your change should respect

These are the rules the project is built on — PRs are reviewed against them:

1. **Don't stick out.** The app must look like Apple made it: system fonts, SF
   Symbols, native materials. Follow the existing design language.
2. **Honesty over decoration.** Every number is a real hardware reading — never
   fake, smooth, or invent values. A stopped fan reads `0 rpm`; an empty state
   says "Empty" / "Nothing found", never a fabricated number. This applies to
   website mock data too (code the mocks; don't invent metrics).
3. **Read freely, write carefully.** Reading sensors is liberal. Anything that
   **writes** to the user's system — fan control, uninstall, cleanup — must be
   guarded, confirmed, reversible where possible, and never touch `/System`,
   `com.apple.*` bundles, or Vitals itself. Changes to `AppUninstaller`,
   `DiskCleaner`, `LeftoverScanner`, `FanController`, `FanDaemon`, and
   `PrivilegedShell` get the most scrutiny and are covered by safety tests — keep
   those tests passing.
4. **Layers that don't leak.** Services talk to hardware and know nothing about
   UI. Models (`@MainActor`) poll and publish. Views only display.

## Reporting bugs & requesting features

Open a GitHub Issue with steps to reproduce, your macOS version, Mac model, and
screenshots where useful. For security vulnerabilities, please **don't** open a
public issue — see [SECURITY.md](./SECURITY.md).

## Questions

Open a discussion or issue, or reach the maintainer via
[rafay99.com](https://rafay99.com). Thanks for helping make Vitals better!
