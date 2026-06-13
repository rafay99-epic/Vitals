# @vitals/backend

The Vitals backend, on [Convex](https://convex.dev). A **local** Convex project —
no cloud account required.

## What it does

One feature today: it caches the **latest GitHub release** so the website doesn't
hit GitHub's API from every visitor's browser.

- `convex/releases.ts`
  - `refresh` (internal action) — fetches `github.com/rafay99-epic/Vitals`
    `releases/latest`, parses the version + `.dmg` size, and upserts one row.
  - `upsert` (internal mutation) — writes the singleton row.
  - `get` (public query) — what the landing page subscribes to; reactive, so a
    new release shows up without a refetch.
- `convex/crons.ts` — runs `refresh` every 6 hours.
- `convex/schema.ts` — a single `releases` row keyed `"latest"`.

On any GitHub failure the cached value is left untouched — never overwritten with
a blank (honesty over decoration).

## Run it locally

```sh
cd apps/backend
CONVEX_AGENT_MODE=anonymous bunx convex dev      # starts the local deployment + watches
```

The first run writes `.env.local` (gitignored) with `CONVEX_URL=http://127.0.0.1:3210`.
Seed the cache once (the cron otherwise fills it on its next tick):

```sh
CONVEX_AGENT_MODE=anonymous bunx convex run releases:refresh '{}'
```

## Wire the website to it

The site reads the cache when `VITE_CONVEX_URL` is set; otherwise it falls back to
fetching GitHub directly, so it always works. For local dev, point the website at
the local deployment:

```sh
# apps/website/.env.local  (gitignored)
VITE_CONVEX_URL=http://127.0.0.1:3210
```

In production set `VITE_CONVEX_URL` to your deployed Convex URL, or leave it unset
to use the GitHub fallback.

## Notes

- `convex/_generated/` is **committed** so the website's `@vitals/backend/api`
  import (and its `tsc -b` build) resolve without running codegen first.
- `CONVEX_AGENT_MODE=anonymous` keeps the CLI from prompting for a Convex account
  in non-interactive shells.
