# CLAUDE.md — Vitals

Vitals is a monorepo: a native macOS hardware monitor + app manager (`apps/desktop`,
Swift/SwiftUI) and its marketing site (`apps/website`, React + Vite + Tailwind v4).
Tooling: bun workspaces + turbo. License: **GPL-3.0**.

## Product philosophy (drives every decision)

1. **Don't stick out** — the app must look like Apple made it. System fonts, SF Symbols,
   native materials.
2. **Honesty over decoration** — every number is a real hardware reading. Never fake,
   smooth, or invent values. A fan at 0 rpm says so. Empty states say "Empty" or
   "Nothing found", never a fabricated number. This applies to website mock data too.
3. **Read freely, write carefully** — reading sensors is liberal; anything that writes
   (fan control, uninstall, cleanup) gets maximum caution, confirmation, and reversibility.
4. **Layers that don't leak** — Services talk to hardware and know nothing about UI.
   Models (@MainActor ObservableObject) poll and publish. Views only display.

## Workflow rules (user's explicit requirements — do not violate)

- **Every feature on its own branch from main** → push → **draft PR**. The user
  squash-merges. Never commit features directly to main.
- **No Claude attribution anywhere**: no `Co-Authored-By`, no "Generated with Claude"
  in commits, PR bodies, or app credits. The app is credited to Syntax Lab Technology /
  Abdul Rafay (rafay99.com).
- After app changes, build + install for the user to test:
  `osascript -e 'tell app "Vitals" to quit'; ditto build/Vitals.app /Applications/Vitals.app`
  then verify with `md5 -q` against the build output, then `open -a Vitals`.
- Verify UI changes visually: activate the window, get bounds via System Events,
  `screencapture -x -R<x,y,w,h>`, and read the image. AX-clicking SwiftUI buttons is
  unreliable — click by screen coordinates or use keyboard shortcuts (⌘1/2/3, ⌘,).

## Versioning & releases

- Version = `0.<total commit count on main>`, computed in `release.yml` and `build.sh`
  (`VITALS_VERSION` env overrides). Currently shipping v0.19.
- Every push to main touching `apps/desktop/**` publishes a GitHub Release (DMG) —
  **gated by a test job**; if tests or lint fail, nothing publishes.
- The version must never go backwards (the updater compares numerically). Never switch
  to path-filtered commit counting — after the monorepo rename it would regress.
- Website + app updater both rely on `releases/latest/download/Vitals.dmg` — never
  rename the DMG asset.

## Commands

```sh
bun install                  # root, once
bun run build / lint / test  # everything via turbo
bun run dmg                  # desktop app + DMG (macOS only)
# desktop directly (from apps/desktop): swift build, swift test, ./build.sh, ./make-dmg.sh
# website e2e locally: E2E_BROWSER="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" bunx turbo test:e2e --filter=website
```

## Desktop architecture

- `Sources/Vitals/Services/` — hardware + system access, UI-free:
  `HIDSensors` (temps via private IOKit HID), `SMC` (fans; key-info cached),
  `SensorSampler` (actor; **all sampling runs off the main thread**), `AppInventory`,
  `LeftoverScanner`, `AppUninstaller`, `DiskCleaner`, `Battery`, `SystemStats`
  (`machHost` cached — `mach_host_self()` leaks a port right per call), `FanDaemon`
  (root helper via launchd; separate process **by design**), `HistoryLogger`, `Updater`.
- `Sources/PrivateSensors/` — C shim for private APIs. CF-returning functions must be
  annotated `CF_RETURNS_RETAINED` so ARC manages them.
- `Models/` — `VitalsModel` (tick → snapshot → publish; `chartHistory` downsampled to
  300 points), `AppsModel`, `CleanupModel`. Tab models are owned by `ContentView` as
  `@StateObject` so scans survive tab switches.
- `Views/` — display only. Main shell is a **stationary header with capsule tabs**
  (Activity Monitor style). There is deliberately **no NavigationSplitView, no window
  toolbar items, no system title bar** — see performance rules.
- Single window (`Window` scene, not `WindowGroup`) and single instance (guard in
  `Main.swift`; the fan daemon's `.prohibited` activation policy excludes it).

## Performance rules (each one was a shipped fix — don't regress)

- **Window geometry must never change from navigation.** Tabs switch content, not
  layout. Don't reintroduce sidebars or toolbar items: AppKit *snaps* (not animates)
  toolbar segments and detail panes on sidebar toggle.
- Swift Charts pay 50–150 ms on first layout → mount through the `Deferred` wrapper
  (Components.swift) so window-open animates against placeholders.
- Grids use **fixed column counts** (`GridItem(.flexible())`), never `.adaptive` —
  adaptive grids reflow column counts mid-animation (cells visibly jump + layout stall).
- Liquid Glass: cards render inside `GlassEffectContainer` (one pass, not N backdrop
  captures). Dashboard stack is a `LazyVStack`. Window backdrop material comes from the
  `glassIntensity` setting.
- Cache NSWorkspace icons (`AppIconCache`); batch streamed updates before publishing
  (sizes apply in batches of 10); give every AsyncStream an `onTermination` that cancels
  its worker; long tasks use `[weak self]` and models cancel in `deinit`.
- Menu-bar sparklines downsample to 100 points.

## Design language (all surfaces follow it: Dashboard, Applications, Cleanup, Storage, Settings, Help, menu-bar panel, and the desktop widgets)

Desktop widgets live in `Sources/Vitals/Widgets/` — a `WidgetManager` of floating `NSPanel`s
hosting SwiftUI bound to the **shared** `VitalsModel`/`AppSettings` (no separate polling).
They're app-owned floating panels, *not* WidgetKit (a SwiftPM widget extension won't load on
macOS 26, and App Groups need a Team ID this ad-hoc build lacks). Toggle them in
Settings → Desktop Widgets.

- **Tabs/segments**: capsule container `.quaternary.opacity(0.45)`, selected segment
  `.quaternary` capsule with `matchedGeometryEffect` sliding indicator, spring
  `(response: 0.28, dampingFraction: 0.85)`.
- **Icon tiles**: 26–28 pt, `RoundedRectangle(cornerRadius: 7)`, fill `tint.opacity(0.14)`,
  symbol 12–13 pt medium in the tint.
- **Cards**: radius 12, fill `.quaternary.opacity(0.3–0.35)`, `strokeBorder(.separator.opacity(0.5))`.
- **Numbers**: `design: .rounded` + `.monospacedDigit()` + `.contentTransition(.numericText())`.
  Heroes: 32 pt semibold value + `.callout` secondary subtitle.
- **Selection**: `checkmark.circle.fill` in accent vs `circle` in `.quaternary`; selected
  surfaces get `Color.accentColor.opacity(0.10)` fill + accent border. Whole card/row is
  the click target.
- Toggles are `.switch` style, small. Symbols use `.hierarchical` rendering.
- Website mocks are **coded components** in this same language — never pasted screenshots.

## Safety rules (test-locked — keep the tests passing)

- Uninstall removes an app and **everything it leaves behind**. User-domain
  leftovers (under `~/Library`, dotfiles) move to the **Trash** (recoverable);
  system-domain leftovers (`/Library/*`, `/Users/Shared`, pkg receipts) are
  removed **permanently as root** via `PrivilegedShell` after explicit
  confirmation. Homebrew-cask apps go through `brew uninstall --cask`; the prefs
  domain is cleared with `defaults delete`. System extensions are **detected and
  surfaced for manual removal**, never force-deleted. The privileged removal
  runs `AppUninstaller.systemRemovalScript`, which re-validates every path
  (allowlisted root, no `..`, never `/System`, basename not `com.apple.*`) — the
  test locks this. Leftover identity is gated: bundle ids validate as
  reverse-DNS, and system name-matches require a distinctive (≥5-char,
  non-generic) name (`LeftoverScanner`).
- Cleanup deletes only regenerable data (caches/logs/trash).
- Cleanup has two depths. **Quick** is user-domain only and stays strict: Apple
  system caches and crash reports are never offered (`shouldOfferCache`/`shouldOfferLog`,
  test-locked). **Deep** adds system categories that need one admin prompt and may remove
  age-gated system caches, system logs, crash reports, system temp, and stale GPU caches —
  but only via `DiskCleaner.systemCleanScript`, which is built from **fixed allowlisted
  roots + `-mtime` age gates** (never UI paths). The script-safety test locks this: every
  delete is age-gated and rooted, never `/System`, never a bare path.
- Privileged work goes through `PrivilegedShell.runAsAdmin` (`do shell script … with
  administrator privileges`) — the one place the app escalates (fan helper + deep clean).
- Never list or touch: anything under `/System`, `com.apple.*` app bundles, Vitals itself.
- Leftover scanning is user-domain only; bundle ids must validate as reverse-DNS before
  touching any path (`LeftoverScanner.isValidBundleID`).
- Fan control: clamp to rated RPM range, admin auth, macOS thermal safety stays under.

## Website

- Implements a Claude Design handoff pixel-faithfully; breakpoint-dependent styles live
  in Tailwind classes (inline styles defeat media queries) — mobile-first responsive.
- `lib/links.ts` is the single source for repo/download/company URLs.
- **SPA on TanStack Router** (file-based). One HTML entry (`index.html` → `main.tsx` →
  `RouterProvider`). Routes are files in `src/routes/` (`__root.tsx`, `index.tsx`,
  `terms.tsx`, `privacy.tsx`); the `@tanstack/router-plugin` generates
  `src/routeTree.gen.ts` — **committed** (the `tsc -b` in `build` runs before `vite build`,
  so it must exist). The root route wires the 404 (`notFoundComponent` → `NotFound`) and
  error page (`errorComponent` → `ErrorScreen`); a top-level `ErrorBoundary` is the outer
  net. Cross-route links use `<Link>`; status pages keep plain `<a href="/">` so they work
  outside the router context too. `router` uses `trailingSlash: 'never'` (old `/terms/`
  redirects to `/terms`). Deep links rely on the SPA fallback — `vercel.json` rewrites all
  paths to `/index.html`, so an unknown path is a **soft 404** (200 + client-rendered
  NotFound), not an HTTP 404.
- Legal pages are the `/terms` and `/privacy` routes. **The privacy policy must match
  reality** — it discloses Vercel Web Analytics (mounted once in `RootLayout`); any new
  data flow must be added there before it ships.
- e2e (`e2e/check.mjs`) drives the system Chrome/Brave (no browser downloads), starts
  its own preview server, and asserts no horizontal overflow at 390/1440 px, plus client
  navigation and the 404/legal routes.

## License & credit (legal requirements)

GPL-3.0 (`LICENSE` at root). The Mole project (github.com/tw93/mole) must stay credited
in: README acknowledgements, `LeftoverScanner.swift` doc comment, the website (Terms §2 +
footer), and the app's Settings → About. Functionality was informed by Mole; no code was
copied.

## Environment gotchas

- The user's shell aliases `cd` through zoxide — it can fail inside chained commands.
  Run Bash from absolute paths or put a plain `cd /abs/path` first.
- Local bun enforces `minimum-release-age` (7 days); use
  `bun install --minimum-release-age=0` only for versions the user already approved.
- This ffmpeg has no libwebp; use `sips` for image conversion.
- `screencapture` captures whatever is frontmost at the coordinates — activate the
  target window first and re-read its bounds in the same osascript.
