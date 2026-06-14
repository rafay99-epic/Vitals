# Convex backend

A thin [Convex](https://convex.dev) backend for the Vitals website — a **live proxy
to the GitHub Releases API**. The frontend calls a Convex action, the action fetches
GitHub server-side and returns the data, and the page shows its shimmer/loading state
while it's in flight. No database, no caching, no cron — deliberately simple.

It lives at the **repo root** (not inside `apps/website`) so any app — the website
today, the desktop app later — can use it. The repo root is the Convex project root:
functions in `convex/`, the `convex` dependency + scripts in the root `package.json`,
deployment in the root `.env.local` (gitignored).

## Functions (`releases.ts`)

- `list` (public action) — every published release, newest first (for `/releases`).
  Throws on a GitHub failure so the page can show its error state.
- `latest` (public action) — the latest release for the download badge, or `null`.
- `lib/github.ts` — reusable, Convex-free `fetchReleases` / `fetchLatestRelease`. The
  website's direct-fetch fallback imports the same module, so there's one parser.

## Rate limit — set a GitHub token

GitHub's **unauthenticated** API allows **60 requests/hour per IP**, and every visitor
shares the Convex deployment's single IP. At low traffic that's fine; to be safe, set a
token (a classic PAT with no scopes, or a fine-grained token with public read is enough)
so requests are authenticated (5,000/hour):

```sh
bunx convex env set GITHUB_TOKEN <token>           # dev deployment
bunx convex env set GITHUB_TOKEN <token> --prod    # production
```

The actions add the auth header automatically when `GITHUB_TOKEN` is set. Never commit
the token — it lives only in the Convex env (and never reaches client code).

## Commands (run from the repo root)

```sh
bun run convex:dev       # start the dev server + watch/push functions
bun run convex:codegen   # regenerate convex/_generated
bun run convex:deploy    # deploy to production (do this when functions change)
```

`convex/_generated/` is **committed** so the website's `@convex/_generated/api` import
and `tsc -b` resolve without a codegen step.

## How the apps consume it

- **Website** imports the API via the `@convex` alias and calls the actions with
  `useAction`. It reads from Convex when `VITE_CONVEX_URL` is set, else falls back to a
  direct GitHub fetch (so it always works). On Vercel, set `VITE_CONVEX_URL` to the
  production Convex **Cloud URL** (`.convex.cloud`).
- **Desktop** (future) would call the deployment over HTTP using `CONVEX_URL`.
