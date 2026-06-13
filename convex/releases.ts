import { v } from 'convex/values'
import { query, internalAction, internalMutation } from './_generated/server'
import { internal } from './_generated/api'

/// Shape returned to the client. Mirrors the website's `LatestRelease`.
const releaseValidator = v.object({
  version: v.string(),
  sizeMB: v.union(v.string(), v.null()),
})

/// The public read: the cached latest release, or null before the first fetch.
/// Reactive — when `refresh` upserts a new version, every subscribed visitor's
/// download badge updates automatically.
export const get = query({
  args: {},
  returns: v.union(releaseValidator, v.null()),
  handler: async (ctx) => {
    const row = await ctx.db
      .query('releases')
      .withIndex('by_key', (q) => q.eq('key', 'latest'))
      .unique()
    if (row === null) return null
    return { version: row.version, sizeMB: row.sizeMB }
  },
})

/// Upserts the singleton row. Internal — only `refresh` calls it.
export const upsert = internalMutation({
  args: { version: v.string(), sizeMB: v.union(v.string(), v.null()) },
  returns: v.null(),
  handler: async (ctx, { version, sizeMB }) => {
    const existing = await ctx.db
      .query('releases')
      .withIndex('by_key', (q) => q.eq('key', 'latest'))
      .unique()
    const fields = { key: 'latest' as const, version, sizeMB, fetchedAt: Date.now() }
    if (existing === null) {
      await ctx.db.insert('releases', fields)
    } else {
      await ctx.db.patch(existing._id, fields)
    }
    return null
  },
})

interface GitHubRelease {
  tag_name?: string
  assets?: { name?: string; size?: number }[]
}

/// Fetches the latest GitHub release and caches it. Internal action (does IO):
/// run on a schedule by the cron, and once on demand to seed the table. On any
/// failure it leaves the last good value untouched — honesty over a blank badge.
export const refresh = internalAction({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    try {
      const res = await fetch('https://api.github.com/repos/rafay99-epic/Vitals/releases/latest', {
        headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'vitals-website' },
        signal: AbortSignal.timeout(10_000),
      })
      if (!res.ok) return null
      const json = (await res.json()) as GitHubRelease
      if (!json.tag_name) return null
      const dmg = json.assets?.find((a) => a.name?.endsWith('.dmg'))
      const sizeMB = dmg?.size ? (dmg.size / 1_048_576).toFixed(1) + ' MB' : null
      await ctx.runMutation(internal.releases.upsert, { version: json.tag_name, sizeMB })
    } catch {
      // Network/parse failure: keep the cached value rather than wipe it.
    }
    return null
  },
})
