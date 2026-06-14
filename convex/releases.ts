import { v } from 'convex/values'
import { RateLimiter, MINUTE } from '@convex-dev/rate-limiter'
import { action } from './_generated/server'
import { components } from './_generated/api'
import { fetchReleases, fetchLatestRelease, fetchLatestPrerelease } from './lib/github'

/// A thin live proxy to the GitHub Releases API — no database, no caching, no
/// schema. The frontend calls these actions, they fetch GitHub server-side, and
/// return the data straight through. The frontend shows the loading/shimmer
/// state while the call is in flight.

/// One release as `list` returns it.
const releaseSummaryValidator = v.object({
  tag: v.string(),
  name: v.string(),
  publishedAt: v.number(),
  url: v.string(),
  dmgUrl: v.union(v.string(), v.null()),
  sizeMB: v.union(v.string(), v.null()),
})

// Optional GitHub token (set `GITHUB_TOKEN` in the Convex dashboard) lifts the
// rate limit from 60 to 5,000 requests/hour. Works without it at low traffic.
const githubToken = () => process.env.GITHUB_TOKEN

// One shared GLOBAL bucket (no per-user key — there's no auth) gating every
// outbound GitHub call across both actions. A token bucket of 30/min sustained
// with a burst capacity of 60 stays far under GitHub's authenticated 5,000/hour
// while never bothering low traffic. The component owns this state internally —
// no host-app table needed.
const rateLimiter = new RateLimiter(components.rateLimiter, {
  githubFetch: { kind: 'token bucket', rate: 30, period: MINUTE, capacity: 60 },
})

/// Every published release, newest first (for the `/releases` page). Throws on a
/// GitHub failure so the caller can show its error state; an empty array means
/// the repo simply has no releases.
export const list = action({
  args: {},
  returns: v.array(releaseSummaryValidator),
  handler: async (ctx) => {
    const status = await rateLimiter.limit(ctx, 'githubFetch')
    if (!status.ok) {
      throw new Error(
        `Too many requests to the GitHub Releases API. Try again in ${Math.ceil(status.retryAfter / 1000)}s.`,
      )
    }
    const releases = await fetchReleases({ token: githubToken() })
    if (releases === null) throw new Error('Could not reach the GitHub Releases API.')
    return releases
  },
})

/// The latest release (for the download badge), or null if it can't be read —
/// the badge just shows no version then, never a fake one.
export const latest = action({
  args: {},
  returns: v.union(v.object({ version: v.string(), sizeMB: v.union(v.string(), v.null()) }), v.null()),
  handler: async (ctx) => {
    const status = await rateLimiter.limit(ctx, 'githubFetch')
    if (!status.ok) return null
    return await fetchLatestRelease({ token: githubToken() })
  },
})

/// The latest Dev *pre-release* (a GitHub prerelease carrying a `Vitals-Dev.dmg`
/// asset), or null if it can't be read — the inverse of `latest`, which drops
/// prereleases. Shares the global rate limiter; returns null on limit/failure so
/// the marketing site degrades gracefully.
export const latestPrerelease = action({
  args: {},
  returns: v.union(
    v.object({
      tag: v.string(),
      name: v.string(),
      branch: v.union(v.string(), v.null()),
      buildNumber: v.union(v.number(), v.null()),
      dmgUrl: v.union(v.string(), v.null()),
      sizeMB: v.union(v.string(), v.null()),
      publishedAt: v.string(),
    }),
    v.null(),
  ),
  handler: async (ctx) => {
    const status = await rateLimiter.limit(ctx, 'githubFetch')
    if (!status.ok) return null
    return await fetchLatestPrerelease({ token: githubToken() })
  },
})
