# UI consistency: the Bedside system

Every Vitals Remote surface (iPhone, Android, the web app served by the Mac, and the marketing site) uses one design system called **Bedside**: the Mac is read like a patient on a bedside monitor. This file is the contract. Read it before touching any UI, follow it exactly, and update it in the same change when the system itself changes.

The interactive reference board (every screen, every state, the component gallery) lives at https://pagepilot.rafay99.com/p/9588508b90304e02b3c4343304bb8171. When the board and this file disagree, this file wins.

The desktop app (`apps/desktop`) keeps its Apple native design language from `CLAUDE.md`. Bedside applies to `packages/ui`, `packages/app`, `apps/mobile`, `apps/web` and `apps/marketing`.

## 1. Principles

1. **Black field, white ink, color belongs to data.** Background is `#000`. Text is white. The only hues on screen are the eight vital channels and the three alarm levels.
2. **One hue per vital, everywhere.** CPU is always PULSE green, memory is always PRESS pink. A color never means two things.
3. **The metaphor never hides the plain label.** Every channel shows its tag and its plain name together: `PULSE` over `CPU`. Screens keep plain titles in accessibility labels.
4. **Honest readings.** A missing value renders `--` and a flat waiting trace, never `0`. Hardware a Mac lacks says so in one sentence ("This Mac is fanless.").
5. **Hairlines, not chrome.** No cards, no pills, no shadows, no rounded boxes in the product. Depth comes from 1 px lines. Only OS surfaces (sheets, notifications, app icons) use the OS radius.
6. **Nothing moves between samples.** A trace redraws once per sample. No loops, pulses, shimmers, spinners or blur. Motion is one shot and driven by data or a touch.
7. **Orders are holds.** Anything that changes the Mac is a press and hold. Anything that ends the session (restart, log out, shut down, kill) is a longer consent hold.
8. **Minimal copy.** One state word per screen. Short sentences. No em dashes, no exclamation marks, no "oops".

## 2. Tokens

Source of truth: `packages/ui/src/theme.ts` (TypeScript) and `packages/ui/src/theme.css` (NativeWind `@theme`, imported by both `apps/mobile/global.css` and `apps/web/global.css`). The marketing site mirrors the same values in `apps/marketing/src/index.css`. Never hardcode a hex in a screen; use the token.

### Neutrals

| Token | Hex | Use |
| --- | --- | --- |
| `bg` | `#000000` | every screen |
| `raise` | `#0a0a0a` | pressed row, selected bed |
| `sheet` | `#0e0e0e` | sheets, dialogs, palette |
| `line` | `#141414` | row hairlines |
| `line2` | `#1f1f1f` | hold rows, sheet top edge |
| `line3` | `#2c2c2c` | field underline, line buttons |
| `mute` | `#5c5c5c` | flat traces, inactive icons. Never text |
| `dim` | `#8b8b8b` | meta text, units |
| `ink2` | `#c9c9c9` | secondary text |
| `ink` | `#ffffff` | primary text, primary button |

### Channels

| Channel | Tag | Plain label | Hex | Wave | Live source |
| --- | --- | --- | --- | --- | --- |
| `pulse` | PULSE | CPU | `#5cf2a6` | `ecg` | `cpu` |
| `eeg` | EEG | GPU | `#f2ec6b` | `eeg` | `gpu` |
| `press` | PRESS | Memory | `#ff6b8b` | `art` | `memoryUsed` |
| `temp` | TEMP | Thermal | `#ffb45c` | `wave` | `cpuTemp` |
| `resp` | RESP | Fans | `#74d4ff` | `wave` | `fan` |
| `oxy` | OXY | Battery | `#c8a8ff` | `pleth` | `battery` |
| `drip` | DRIP | Power | `#6f9bff` | `step` | `socWatts` |
| `tele` | TELE | Network | `#b9c4d0` | `bars` | `netIn` |

The table lives in code as `channels` in `theme.ts`. Screens look a channel up by key; they never restate its color, tag or label.

### Alarms

| Token | Hex | Use |
| --- | --- | --- |
| `alarmHigh` | `#ff4d6d` | critical alarm bar, `HIGH` tag |
| `alarmMedium` | `#ffb45c` | warning alarm bar, `ELEV` tag, reconnecting bar |
| `alarmLow` | `#74d4ff` | advisory bar |

Alarms are always a **filled bar with black text**, so they never depend on hue alone.

### Type

Three bundled families, loaded through `expo-font` before the first screen renders (`fontAssets` in `packages/ui/src/fonts.ts`). The marketing site self hosts the same files.

| Role | Family | NativeWind class | Size (pt / sp / px) | Use |
| --- | --- | --- | --- | --- |
| hero | Instrument Serif | `font-display text-hero` | 56 / 56 / 96 | pairing success, marketing hero |
| xl | Instrument Serif | `font-display text-xl2` | 56 / 56 / 64 | detail headline value, web wall numerals |
| state | Instrument Serif Italic | `font-display-italic text-state` | 46 / 46 / 40 | the state word, one per screen |
| l | Instrument Serif | `font-display text-l` | 44 / 44 / 44 | screen titles, channel numerals |
| m | Instrument Serif | `font-display text-m` | 26 / 26 / 30 | row labels, sheet titles |
| s | Instrument Serif | `font-display text-s` | 20 / 20 / 22 | bed names, chips |
| body | Geist | `font-text text-body` | 15 / 15 / 14 | sentences, notifications |
| small | Geist | `font-text text-small` | 13 / 13 / 12.5 | help text |
| tag | Geist Mono Medium, caps, tracking 10% | `font-code-medium text-tag uppercase tracking-widest` | 10 | channel tags, section labels |
| meta | Geist Mono | `font-code text-meta` | 11 / 11 / 10.5 | units, timestamps, hints |

Numerals always use tabular figures. Serif sizes follow Dynamic Type and Android font scale, capped at 1.3x (`maxFontSizeMultiplier`); mono caps at 1.5x.

### Space, size, radius

- 4 pt grid. Screen gutter 22. Section gap 32.
- Row heights: channel 88, compact channel 64, list row 56, bed 58, hold 92.
- Touch targets never under 44 pt (iOS, web) or 48 dp (Android).
- Radius 0 in the product. OS sheet top 26 (iOS) or 28 (Android), web dialog 12.

### Motion

| Token | Duration | Easing | Use |
| --- | --- | --- | --- |
| `sample` | 400 ms | `(.2,.8,.2,1)` | trace head, numeral swap, state color |
| `release` | 220 ms | ease out | hold retracts when let go early |
| `hold` | 1300 ms | linear | Rest, Lights out, Lock, Calm down |
| `consent` | 2600 ms | linear | Restart, Log out, Shut down, Kill, Force quit, Unpair |
| `sheet` | 280 ms | `(.2,.8,.2,1)` | sheets, palette |
| `alarmIn` | 260 ms | `(.2,.8,.2,1)` | alarm bar, once per alarm |
| `flatline` | 600 ms | ease in | connection lost |
| `toast` | 200 ms in, 4 s hold | ease out | receipts and confirmations |

Data motion lives in `packages/ui/src/motion.ts` and is built into the kit, so screens get it for free: **arrive** (`rise`: sections, readout cells and channel rows fade up 8 px the first time they mount; readout cells and channel rows stagger 45 ms by position, sections arrive together; plain rows fade in with `swap`), **change** (`swap`: when a readout value or the state word changes, the new one fades in over the old), **shift** (`settle`: when an alarm bar or row appears or leaves, everything below slides to its new place; native only, the web build skips it) and **leave** (`leave`: alarm bars and toasts fade out). Never animate between samples beyond these, and never count numbers up from zero.

Reduced motion (`useReducedMotion`): traces redraw in place without the head, state color changes instantly, sheets and bars appear without sliding. Holds keep their duration; it is a safety rule, not decoration.

### Haptics

All through `packages/app/src/lib/haptics.ts` (web build is a no-op). Tab or chip change: `select`. Hold starts: `soft`. Hold lands: `success`. Consent lands: `heavy`. Switch: `light`. Alarm while open: `warning`. Rejected order or failed pairing: `error`. Samples never vibrate.

## 3. Components

Visual components that know nothing about the Mac connection live in `packages/ui/src` and are exported from `@vitals/ui`. Components that read the session or live stores (`LiveText`, `TabHeader`, `AlertBanner`, `PendingOrder`) live in `packages/app/src/components`. A screen composes these; it never restyles them with ad hoc classes. If a screen needs something neither layer has, add it to the right layer (and to this table), never inline a one-off.

| Component | File | Use it for | States and rules |
| --- | --- | --- | --- |
| `Serif`, `Sans`, `Mono`, `Tag` | `typography.tsx` | every piece of text | `size` and `tone` props map to the type table; never set font classes by hand |
| `Screen` | `layout/Screen.tsx` | every screen body | owns safe area, scroll, gutter, pull to refresh |
| `Columns` | `layout/Columns.tsx` | a tab that splits on wide screens | one column on phones; main plus a 420 px side column at 900 px and wider |
| `ScreenHeader` | `layout/ScreenHeader.tsx` | top of every tab | who line (Mac name + link status), state word, one meta line |
| `BackHeader` | `layout/ScreenHeader.tsx` | pushed screens | parent name with a chevron; Android hides the label |
| `SectionHeader` | `layout/Section.tsx` | groups inside a screen | mono caps title, optional trailing meta. No subtitle line |
| `Row` | `rows/Row.tsx` | settings, info, orders without a hold | serif label, optional mono detail, value, decorative `trailing` or an interactive `control` (keeps its own role), chevron when pressable |
| `KeyValueGrid` | `rows/KeyValueGrid.tsx` | detail numbers | two columns, hairline grid |
| `StackBar` | `rows/StackBar.tsx` | composition (memory, storage) | flat segments with a text legend |
| `EmptyState` | `rows/EmptyState.tsx` | nothing to show yet | flat line, one serif sentence, one meta line |
| `ChannelRow` | `channel/ChannelRow.tsx` | one vital on the Chart | `normal`, `elevated` (ELEV tag), `alarm` (HIGH tag, tinted), `flat` (no signal), `waiting`; `compact` size for GPU, power, network |
| `Trace` | `channel/Trace.tsx` | live waveform | Skia, path computed on the UI thread from a `SeriesSource`. Never re-renders React per sample |
| `HistoryChart` | `channel/HistoryChart.tsx` | 1 h / 24 h / 7 d history | min/max band, mean line, peak marker, time labels |
| `Spark` | `channel/Spark.tsx` | per process and per core traces | 1.3 px line, no fill |
| `LiveText` | `packages/app/src/components/LiveText.tsx` | any live number | a leaf subscriber with a module level selector, so only that text re-renders |
| `TabHeader` | `packages/app/src/components/TabHeader.tsx` | top of each tab | binds `ScreenHeader` to the Mac name, link label and state word |
| `AlertBanner`, `PendingOrder` | `packages/app/src/components/` | open alarms and orders in their grace window | hide Calm down and Cancel when the device lacks the operate scope |
| `HoldRow` | `controls/HoldRow.tsx` | every order that changes the Mac | `idle`, `holding` (trace draws across), `done`, `danger`, `locked`; `consent` duration for session enders |
| `Button` | `controls/Button.tsx` | sheet and form actions | `primary` (white), `line`, `text`, `danger`; sizes `md`, `sm` |
| `Chips` | `controls/Chips.tsx` | small exclusive choices (1 h, 4 h, Forever) | selected chip takes `pulse` |
| `Segmented` | `controls/Segmented.tsx` | view switches (BY CPU / BY MEMORY, ranges) | mono caps with an underline |
| `BeatSwitch` | `controls/BeatSwitch.tsx` | on/off | flat line off, a beat on |
| `Slider` | `controls/Slider.tsx` | volume, thresholds | hairline track, 2 px thumb, value beside it |
| `Field` | `controls/Field.tsx` | text input | underline; `mono` variant for addresses and bundle ids; `error` |
| `CodeInput` | `controls/CodeInput.tsx` | pairing code | three groups of four, caps, one-time-code autofill |
| `AlarmBanner` | `feedback/AlarmBanner.tsx` | alarms and connection trouble | `high`, `medium`, `low`; one action |
| `Toast` | `feedback/Toast.tsx` | receipts | white bar, one action, 4 s |
| `Sheet` | `feedback/Sheet.tsx` | actions on a thing, confirmations | title, meta line, `SheetAction` rows, a Cancel |
| `BedRow` | `ward/BedRow.tsx` | a process | bed number, name, meta, spark, number; `paused`, `selected` |
| `WardHeader` | `ward/BedRow.tsx` | a process group | italic serif name, totals |
| `TabBar` | `nav/TabBar.tsx` | primary navigation | bottom bar on phones, left rail at 900 px and wider |
| `Glyph`, `Mark` | `nav/Glyph.tsx` | tab icons and the logo | the single beat mark; never recolor or glow it |

## 4. Screens

Tabs, in order: **Chart, Orders, Ward, Alarms, Record**. Each tab is one screen with depth inside it; no tabs inside tabs.

| Screen | Path | Contents |
| --- | --- | --- |
| Chart | `features/chart/ChartScreen.tsx` | header with state word; 5 full channels (PULSE, PRESS, TEMP, RESP, OXY) then 3 compact (EEG, DRIP, TELE). Wide: monitor wall with lanes, numerals column and event strip |
| Channel detail | `features/chart/ChannelScreen.tsx` | back header, channel name as state word, big numeral, wide trace, range switch + `HistoryChart`, `KeyValueGrid`, channel specifics (cores, composition, sensors, fans, battery health, interfaces) |
| Orders | `features/orders/OrdersScreen.tsx` | Rest, Lights out, Lock, Stay awake chips + Allow sleep, Volume + Mute, Clipboard, Open on Mac, Locate, Scenes, Discharge (Restart, Log out, Shut down behind consent), Log of receipts |
| Ward | `features/ward/WardScreen.tsx` | BY CPU / BY MEMORY, wards (Agents, Emulators, Dev servers, Browsers, Other) with beds; tap a bed for its sheet. Wide: table plus inspector |
| Alarms | `features/alarms/AlarmsScreen.tsx` | readouts (Pressure, Swap, Thermal), Calm hold + Undo, rule switches and thresholds, wards a calm touches, alarm log for this session |
| Record | `features/record/RecordScreen.tsx` | Mac, This device, Updates, Permissions, Running apps, Launch, Emulators, Unpair; Diagnostics in the dev build |
| Onboarding | `features/onboarding/OnboardingScreen.tsx` | first launch on native only: welcome, get Vitals for Mac (brew command, share link), turn on Remote, Tailscale on both, pair. "I already have it" skips to pairing |
| Pair | `features/pairing/PairScreen.tsx` | scan, enter code (+ Mac address on native), progress steps, Admitted, errors |
| Alerts explainer | `features/pairing/AlertsScreen.tsx` | shown once after Admitted, before the OS prompt |
| Link states | `ScreenHeader` + `features/chart/LinkState.tsx` | Connecting, Reconnecting, Paused, No signal, Removed, Out of step |
| Update gate | `features/updates/UpdateGate.tsx` | blocks the app while a mandatory update downloads: the beat draws across with the real download progress, a hero percent, Check · Download · Restart; the reload screen is black so there is never a white flash |
| Updates | `features/updates/UpdatesScreen.tsx` | from Record: build, channel, running update, runtime, publish time, Google Play store version, Check for updates, Update from Google Play when the store has a newer binary |
| Store update sheet | `features/updates/PlayUpdateSheet.tsx` | Android only: once per new Google Play version on launch, "A new Vitals is out." with Update now (Play flexible download, then the app restarts into it) |
| Diagnostics | `features/diagnostics/DiagnosticsScreen.tsx` | dev build only: link timeline, RPC latency, frame rate, renders, memory, update info, log export |

### State word

One word per screen header, chosen by priority: alarm summary, **No signal.**, **Fever.** (thermal serious or worse), **Pressure rising.** (memory pressure warning or worse), **Breathing hard.** (fans above 80% of max), **Racing.** (CPU above 75), **Elevated.** (CPU 45 to 75), **Resting.** Transient words: **Admitted.** after pairing, **Calmed.** for 10 s after a calm, **Asleep.** while the Mac sleeps. The logic is `stateWord()` in `packages/app/src/state/vitals.ts`; screens never compute their own.

### Icons and splash

The mark is the single beat in `pulse` on black. iOS ships light (black field), dark (transparent field) and tinted (white beat) icons; Android ships an adaptive foreground on black plus a monochrome layer for themed icons; the Mac uses an Icon Composer file per channel (green Stable, amber Nightly, violet Dev). The dev phone build adds a violet DEV badge. On the native phone builds the splash is the beat alone on black and stays up through the launch update check; web and the Mac have no splash.

## 5. Platforms

| Topic | iOS | Android | Web |
| --- | --- | --- | --- |
| Navigation | bottom bar, 5 tabs | bottom bar, active indicator behind the glyph | left rail at 900 px, bottom bar below; every tab has a URL |
| Back | edge swipe + `BackHeader` | predictive back, no label | browser back, Esc closes sheets |
| Sheets | slide up, 26 radius | slide up, 28 radius | bottom sheet under 720 px, centered dialog above |
| Holds | long press, progress on the UI thread | same, no ripple on hold rows | pointer hold, or Space/Enter held on a focused row |
| Haptics | expo-haptics | expo-haptics | none |
| Credentials | Keychain, after first unlock | SecureStore | HttpOnly cookie only |
| Alerts | background task + local notification with Calm down | WorkManager + high importance channel | Notification API while the tab is open |
| Updates | mandatory OTA (`expo-updates`) | mandatory OTA | ships with the Mac app |

## 6. Accessibility

- Channel rows read as one sentence: "CPU, 23 percent, resting." Traces are hidden from screen readers.
- Every hold has an `accessibilityActions` alternative: the activate action commits it. Session enders already sit behind a consent sheet, so assistive users always confirm twice for them.
- Alarm and elevated states are written (`HIGH`, `ELEV`, `paused`), never color alone.
- Contrast: body text is `ink`, `ink2` or `dim`; `mute` is never used for text.
- Focus ring on web: 2 px, visible, never removed.

## 7. Performance rules

- Live numbers are leaf components subscribed with `useSelect`; parents never subscribe to `live.latest` to pass numbers down.
- Traces, holds and switches animate on the UI thread (Reanimated shared values feeding Skia). No `setState` per sample.
- Lists of beds and rows use stable keys (`pid-startTimeMs`, ids), never indexes.
- No inline object or array literals created per render for props that cross into memoized children; derive with selectors.
- React Compiler is on; do not hand-write `useMemo`/`useCallback` unless a hook dependency needs a stable identity.
- Subscriptions are scoped to focus (`useFocusEffect`) so hidden tabs stop their watches.

## 8. Code rules for UI

- No comments in components; names carry the meaning.
- No `any`, no casts, no non-null assertions. Variants are discriminated unions, looked up with `Record` maps, not nested ternaries or `if` chains.
- One component per concept. A second copy of a row, header or trace is a bug: extend the kit component instead.
- Copy follows section 1: verbs for orders, one state word, units in mono.

## 9. Review checklist

Before merging any UI change:

1. Every color comes from a token; every channel from `channels`.
2. No card, pill, shadow or rounded container was added.
3. No looping animation; reduced motion checked.
4. Every new live number is a leaf subscriber.
5. Missing data renders `--` or an `EmptyState`, never `0`.
6. Screen reader labels read as sentences; holds have their alternative.
7. Phone (390), tablet (820) and wide web (1296) layouts checked.
8. This file still matches the code.
