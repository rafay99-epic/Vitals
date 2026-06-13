import { defineSchema, defineTable } from 'convex/server'
import { v } from 'convex/values'

/// The single source of truth for the website's "latest release" badge. One
/// singleton row keyed `"latest"` — the GitHub release fetched server-side,
/// cached here, and read reactively by the landing page. `sizeMB` is null when
/// the release has no `.dmg` asset (honest empty state, never a fake number).
export default defineSchema({
  releases: defineTable({
    key: v.literal('latest'),
    version: v.string(),
    sizeMB: v.union(v.string(), v.null()),
    fetchedAt: v.number(),
  }).index('by_key', ['key']),

  /// The full, cached list of GitHub releases — one row per published (non-draft,
  /// non-prerelease) release. Reconciled by `syncList` from a single server-side
  /// GitHub call and read, ordered newest-first, by the website's `/releases`
  /// page. Rows are lean (no notes body — the page links out to GitHub for those).
  releaseList: defineTable({
    tag: v.string(), //          e.g. "v0.26"
    name: v.string(), //         release title (falls back to tag if empty)
    publishedAt: v.number(), //  ms epoch, for ordering
    url: v.string(), //          GitHub release html_url
    dmgUrl: v.union(v.string(), v.null()), //   the .dmg asset's browser_download_url
    sizeMB: v.union(v.string(), v.null()),
  })
    .index('by_tag', ['tag']) //                reconcile lookups
    .index('by_published', ['publishedAt']), // ordered listing
})
