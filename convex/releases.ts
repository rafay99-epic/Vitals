import { v } from 'convex/values'
import { action } from './_generated/server'
import { fetchReleases, fetchLatestRelease } from './lib/github'

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

/// Every published release, newest first (for the `/releases` page). Throws on a
/// GitHub failure so the caller can show its error state; an empty array means
/// the repo simply has no releases.
export const list = action({
  args: {},
  returns: v.array(releaseSummaryValidator),
  handler: async () => {
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
  handler: async () => await fetchLatestRelease({ token: githubToken() }),
})
