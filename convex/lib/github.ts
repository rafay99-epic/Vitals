/// Reusable, Convex-free GitHub release fetcher. No Convex imports — just
/// `fetch` + parse — so it can be unit-tested in isolation and reused by any
/// future action. Returns `null` on any failure (network, non-2xx, malformed)
/// so callers keep their last cached value rather than blank it.

/// The shape of a GitHub release payload we care about.
interface GitHubReleasePayload {
  tag_name?: string
  name?: string | null
  html_url?: string
  published_at?: string | null
  draft?: boolean
  prerelease?: boolean
  assets?: { name?: string; size?: number; browser_download_url?: string }[]
}

/// One release as the website's `/releases` page consumes it: tag, title, the
/// publish time (ms epoch, for ordering), the GitHub html_url, and the `.dmg`
/// asset's download URL + human `sizeMB` — both null when there's no `.dmg`
/// (honest empty state, never a fake number).
export interface ReleaseSummary {
  tag: string
  name: string
  publishedAt: number
  url: string
  dmgUrl: string | null
  sizeMB: string | null
}

/// Default repository (owner/name) and request timeout.
const DEFAULT_REPO = 'rafay99-epic/Vitals'
const DEFAULT_TIMEOUT_MS = 10_000
const BYTES_PER_MB = 1_048_576

/// Formats a byte count as a `"12.3 MB"` string. Returns `null` for missing or
/// non-positive sizes so the badge stays honest.
export function bytesToMB(bytes: number | undefined): string | null {
  if (!bytes || bytes <= 0) return null
  return (bytes / BYTES_PER_MB).toFixed(1) + ' MB'
}

/// Fetches the full release list for `repo` (one call, up to 100 releases).
/// Resolves to a newest-first array of `ReleaseSummary`, or `null` on any
/// failure (network error, non-2xx, non-array body) so callers keep their
/// cached rows. Drafts, prereleases, and tag-less releases are filtered out.
export async function fetchReleases(
  repo: string = DEFAULT_REPO,
  timeoutMs: number = DEFAULT_TIMEOUT_MS,
): Promise<ReleaseSummary[] | null> {
  try {
    const res = await fetch(`https://api.github.com/repos/${repo}/releases?per_page=100`, {
      headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'vitals-website' },
      signal: AbortSignal.timeout(timeoutMs),
    })
    if (!res.ok) return null
    const json = (await res.json()) as unknown
    if (!Array.isArray(json)) return null

    const summaries: ReleaseSummary[] = []
    for (const raw of json as GitHubReleasePayload[]) {
      if (raw.draft || raw.prerelease || !raw.tag_name) continue
      const dmg = raw.assets?.find((a) => a.name?.endsWith('.dmg'))
      summaries.push({
        tag: raw.tag_name,
        name: raw.name && raw.name.length > 0 ? raw.name : raw.tag_name,
        publishedAt: raw.published_at ? Date.parse(raw.published_at) : 0,
        url: raw.html_url ?? '',
        dmgUrl: dmg?.browser_download_url ?? null,
        sizeMB: bytesToMB(dmg?.size),
      })
    }
    // Newest first — the page lists in this order and `refresh` derives latest
    // from index 0.
    summaries.sort((a, b) => b.publishedAt - a.publishedAt)
    return summaries
  } catch {
    // Network/parse failure: signal "no update" so the caller keeps its cache.
    return null
  }
}
