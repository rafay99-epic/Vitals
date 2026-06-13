import { cronJobs } from 'convex/server'
import { internal } from './_generated/api'

/// Refresh the cached GitHub release hourly as a backstop. (A new release also
/// triggers an immediate refresh via the Convex GitHub Action on
/// `release: published`, so the badge updates within seconds of a publish — this
/// just covers anything missed.) GitHub's API is hit once per interval from the
/// server, not once per visitor, so the per-IP rate limit is a non-issue.
const crons = cronJobs()
crons.interval('refresh latest release', { hours: 1 }, internal.releases.refresh, {})
export default crons
