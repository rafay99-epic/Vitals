# Security Policy

Vitals takes security seriously — especially anything that could let code run with
administrator privileges, delete user data, or tamper with the update pipeline.
If you believe you've found a vulnerability, please report it privately.

## Supported versions

Security fixes are applied to the **latest stable release** on `main` (published
as [GitHub Releases](https://github.com/rafay99-epic/Vitals/releases) and the
`rafay99-epic/apps/vitals` Homebrew cask). Older builds are not supported.

| Channel | Supported for security fixes |
| --- | --- |
| Latest stable (`Vitals.dmg` / Homebrew `vitals`) | Yes |
| Latest Dev pre-release (`Vitals-Dev.dmg` / Homebrew `vitals-dev`) | Best-effort — Dev is a testing channel; prefer reporting against Stable |
| Older releases | No |

## Reporting a vulnerability

**Do not open a public GitHub issue** for security vulnerabilities. Public
disclosure before a fix is available puts users at risk.

Report privately using one of these channels:

1. **GitHub Security Advisories (preferred):**
   [Report a vulnerability](https://github.com/rafay99-epic/Vitals/security/advisories/new)
   on this repository. GitHub keeps the report confidential until we publish an
   advisory.

2. **Direct contact:** email
   [99marafay@gmail.com](mailto:99marafay@gmail.com) or reach the maintainer via
   [rafay99.com](https://rafay99.com). Use a clear subject line such as
   `Vitals security report`.

Please include as much of the following as you can:

- A description of the issue and its potential impact
- Steps to reproduce, or a proof of concept if you have one
- Which component is affected (desktop app, updater, website, backend)
- Your Vitals version (or commit SHA), macOS version, and Mac model if relevant
- Whether you'd like credit in a release note (optional)

## What happens next

- **Acknowledgment:** we aim to confirm receipt within **3 business days**.
- **Assessment:** we will investigate severity and reproducibility, and keep you
  updated on progress when possible.
- **Fix & disclosure:** confirmed issues are fixed on `main`, released through
  the normal pipeline, and disclosed via a GitHub Security Advisory (or, for
  lower-severity items, release notes) once a fix is available.
- **Coordination:** please allow reasonable time to develop and test a fix before
  public disclosure. We are happy to coordinate disclosure timing with you.

We do not offer a paid bug-bounty program at this time, but we are grateful for
responsible reports and will credit reporters by name in advisories or release
notes when they ask.

## Scope

### In scope

- **Vitals macOS app** (`apps/desktop`) — including sensor access, fan control,
  the root fan helper (`FanDaemon`), app uninstall/cleanup, privileged shell
  execution (`PrivilegedShell`), local settings/history, and the in-app updater
  (GitHub release download and install).
- **Vitals website** (`apps/website`) — pages, client-side code, and build output
  served to users.
- **Convex backend** (`convex/`) — functions and configuration in this
  repository (the live GitHub release proxy).

### Out of scope

- Vulnerabilities in **macOS, Apple hardware/firmware, or third-party apps** Vitals
  merely reads or manages.
- Issues in **GitHub, Vercel, Convex Cloud, or Homebrew** infrastructure outside
  this repository's control.
- The separate **[homebrew-apps](https://github.com/rafay99-epic/homebrew-apps)**
  tap (report cask issues there unless the vulnerability is in Vitals itself).
- **Social engineering**, physical access, or attacks that require the victim to
  manually approve an unrelated admin prompt unrelated to Vitals.
- **Denial-of-service** against GitHub's API or other shared infrastructure,
  except where Vitals' own code amplifies impact beyond normal client usage.

If you're unsure whether something is in scope, report it anyway — we'd rather
triage a false positive than miss a real issue.

## Security-sensitive areas

These parts of the codebase receive extra scrutiny in review and are covered by
automated safety tests. Reports involving them are especially welcome:

- **`PrivilegedShell`** — the only path that escalates to administrator
  privileges (`do shell script … with administrator privileges`).
- **`AppUninstaller` / `LeftoverScanner`** — permanent deletion and Trash moves;
  system paths are allowlisted and re-validated in `systemRemovalScript`.
- **`DiskCleaner`** — Quick vs Deep cleanup; system deletes use fixed allowlisted
  roots and age gates in `systemCleanScript`, never arbitrary UI paths.
- **`FanController` / `FanDaemon`** — fan RPM writes via a separate root helper.
- **`Updater`** — release fetch, DMG download, and in-place app replacement.

Reading sensors, displaying stats, and local CSV/history logging are intentionally
liberal; **writes to the system** are where the highest bar applies.

## Safe harbor

We support good-faith security research on Vitals. If you:

- Report issues through the channels above,
- Avoid accessing or exfiltrating other users' data,
- Do not degrade service for others, and
- Do not exploit a finding beyond what's needed to demonstrate impact,

we will not pursue legal action or DMCA claims against you for that research.
This does not authorize attacks against third-party services (GitHub, Vercel,
etc.) or other people's machines.

## Non-security bugs

For crashes, UI glitches, and feature requests that are **not** security-related,
open a [GitHub Issue](https://github.com/rafay99-epic/Vitals/issues) with steps
to reproduce, macOS version, and Mac model. See [CONTRIBUTING.md](./CONTRIBUTING.md).

---

Maintained by **Syntax Lab Technology** · [Abdul Rafay — rafay99.com](https://rafay99.com)
