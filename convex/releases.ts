import { v } from 'convex/values'
import { query, internalAction, internalMutation } from './_generated/server'
import { internal } from './_generated/api'
import { fetchReleases } from './lib/github'

/// Shape returned to the client for the singleton. Mirrors the website's
/// `LatestRelease`.
const releaseValidator = v.object({
  version: v.string(),
  sizeMB: v.union(v.string(), v.null()),
})

/// One row of the full release list, as `list` returns it and `syncList`
/// accepts it. Shared so the public read and the reconcile mutation can't drift.
const releaseSummaryValidator = v.object({
  tag: v.string(),
  name: v.string(),
  publishedAt: v.number(),
  url: v.string(),
  dmgUrl: v.union(v.string(), v.null()),
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

/// The public read for the `/releases` page: every cached release, newest first.
/// Reactive — `syncList` reconciles the table and every subscriber re-renders.
export const list = query({
  args: {},
  returns: v.array(releaseSummaryValidator),
  handler: async (ctx) => {
    const rows = await ctx.db
      .query('releaseList')
      .withIndex('by_published')
      .order('desc')
      .take(50)
    // Strip `_id`/`_creationTime` so the shape matches the validator exactly.
    return rows.map((r) => ({
      tag: r.tag,
      name: r.name,
      publishedAt: r.publishedAt,
      url: r.url,
      dmgUrl: r.dmgUrl,
      sizeMB: r.sizeMB,
    }))
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

/// Reconciles the `releaseList` table against a freshly-fetched list. Internal —
/// only `refresh` calls it. Loads every existing row once (`.collect()` — bounded
/// by the release count) and, keyed by tag: inserts new releases, patches changed
/// ones (skipping the write when every field is identical), and deletes rows
/// whose tag has disappeared. No needless writes, so subscribers only re-render
/// on a real change.
export const syncList = internalMutation({
  args: { releases: v.array(releaseSummaryValidator) },
  returns: v.null(),
  handler: async (ctx, { releases }) => {
    const existing = await ctx.db.query('releaseList').collect()
    const byTag = new Map(existing.map((row) => [row.tag, row]))
    const seen = new Set<string>()

    for (const rel of releases) {
      seen.add(rel.tag)
      const row = byTag.get(rel.tag)
      if (row === undefined) {
        await ctx.db.insert('releaseList', rel)
        continue
      }
      // Patch only when something actually differs.
      if (
        row.name !== rel.name ||
        row.publishedAt !== rel.publishedAt ||
        row.url !== rel.url ||
        row.dmgUrl !== rel.dmgUrl ||
        row.sizeMB !== rel.sizeMB
      ) {
        await ctx.db.patch(row._id, {
          name: rel.name,
          publishedAt: rel.publishedAt,
          url: rel.url,
          dmgUrl: rel.dmgUrl,
          sizeMB: rel.sizeMB,
        })
      }
    }

    // Drop rows whose tag is no longer present upstream.
    for (const row of existing) {
      if (!seen.has(row.tag)) {
        await ctx.db.delete(row._id)
      }
    }
    return null
  },
})

/// Fetches the GitHub release list and caches both the full list and the latest
/// singleton from ONE call. Internal action (does IO), invoked event-driven —
/// not polled: the CI `convex.yml` runs it on `release: published` (so the page
/// and badge update within seconds of a new app release) and once after each
/// backend deploy (to seed/heal the cache). The fetch/parse lives in the reusable
/// `lib/github` helper; on any failure it returns null and we leave the last good
/// values untouched — honesty over a blank page.
export const refresh = internalAction({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    const releases = await fetchReleases()
    if (releases === null) return null
    await ctx.runMutation(internal.releases.syncList, { releases })
    // Newest first — index 0 is the latest. Guard the empty array.
    const latest = releases[0]
    if (latest !== undefined) {
      await ctx.runMutation(internal.releases.upsert, {
        version: latest.tag,
        sizeMB: latest.sizeMB,
      })
    }
    return null
  },
})
