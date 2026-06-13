import { cronJobs } from 'convex/server'
import { internal } from './_generated/api'

/// Refresh the cached GitHub release a few times a day. GitHub's API is hit
/// once per interval from the server (not once per visitor), so the per-IP rate
/// limit is a non-issue and the badge stays current.
const crons = cronJobs()
crons.interval('refresh latest release', { hours: 6 }, internal.releases.refresh, {})
export default crons
