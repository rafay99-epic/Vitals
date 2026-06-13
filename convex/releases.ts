import { v } from 'convex/values'
import { query, internalAction, internalMutation } from './_generated/server'
import { internal } from './_generated/api'
import { fetchLatestRelease } from './lib/github'

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
    // Nothing changed → don't write. Skips a needless mutation and avoids
    // re-running every subscriber's `get` query for an identical value.
    if (existing !== null && existing.version === version && existing.sizeMB === sizeMB) {
      return null
    }
    const fields = { key: 'latest' as const, version, sizeMB, fetchedAt: Date.now() }
    if (existing === null) {
      await ctx.db.insert('releases', fields)
    } else {
      await ctx.db.patch(existing._id, fields)
    }
    return null
  },
})

/// Fetches the latest GitHub release and caches it. Internal action (does IO),
/// invoked event-driven — not polled: the CI `convex.yml` runs it on
/// `release: published` (so the badge updates within seconds of a new app
/// release) and once after each backend deploy (to seed/heal the cache). The
/// fetch/parse lives in the reusable `lib/github` helper; on any failure it
/// returns null and we leave the last good value untouched — honesty over a
/// blank badge.
export const refresh = internalAction({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    const release = await fetchLatestRelease()
    if (release !== null) {
      await ctx.runMutation(internal.releases.upsert, release)
    }
    return null
  },
})
