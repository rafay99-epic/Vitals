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
})
