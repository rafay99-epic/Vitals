# Convex backend

The shared Vitals backend, on [Convex](https://convex.dev). It lives at the **repo
root** (not inside `apps/website`) so any app — the website today, the desktop app
later — can use it.

The repo root is the Convex project root: functions are in `convex/`, the `convex`
dependency and scripts are in the root `package.json`, and the deployment is read
from the root `.env.local` (gitignored).

## What it does

One feature today: it caches the **latest GitHub release** so the website doesn't
hit GitHub's API from every visitor's browser.

- `releases.ts`
  - `refresh` (internal action) — fetches `github.com/rafay99-epic/Vitals`
    `releases/latest`, parses the version + `.dmg` size, upserts one row.
  - `upsert` (internal mutation) — writes the singleton row.
  - `get` (public query) — what the landing page subscribes to; reactive.
- `lib/github.ts` — reusable, Convex-free GitHub fetch/parse (shared helpers live in `lib/`).
- `schema.ts` — a single `releases` row keyed `"latest"`.

On any GitHub failure the cached value is left untouched — never blanked. `upsert` also
skips the write when nothing changed.

**No cron.** The cached release only changes when a release is published, so refreshing is
**event-driven** (it would waste free-tier function calls to poll): the CI workflow
(`.github/workflows/convex.yml`) refreshes on every backend deploy and on
`release: published`. A *daily* cron would be a fine optional backstop; an hourly one isn't
worth it.

## Commands (run from the repo root)

```sh
bun run convex:dev       # start the dev server + watch/push functions
bun run convex:codegen   # regenerate convex/_generated without deploying
bun run convex:deploy    # deploy to the production deployment

# headless / non-interactive shells: force an anonymous local deployment
CONVEX_AGENT_MODE=anonymous bunx convex dev

# seed the cache once (CI also seeds it on every deploy and on each release)
bunx convex run releases:refresh '{}'
```

## How the apps consume it

- **Website** imports the typed API via the `@convex` alias (configured in
  `apps/website/vite.config.ts` + `tsconfig.app.json`): `import { api } from
  '@convex/_generated/api'`. It reads the cache when `VITE_CONVEX_URL` is set,
  else falls back to a direct GitHub fetch (so it always works). Point local dev
  at the deployment with `apps/website/.env.local`:

  ```sh
  VITE_CONVEX_URL=<your CONVEX_URL from the root .env.local>
  ```

- **Desktop** (future) would call the deployment over HTTP using `CONVEX_URL`.

`convex/_generated/` is **committed** so the website's `@convex/_generated/api`
import and `tsc -b` resolve without a codegen step. After changing a schema or
function, re-run `bun run convex:codegen` (or `convex:dev`) to regenerate it.
