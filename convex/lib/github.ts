/// Reusable, Convex-free GitHub release fetcher. No Convex imports — just
/// `fetch` + parse — so it can be unit-tested in isolation and reused by any
/// future action. Returns `null` on any failure (network, non-2xx, malformed)
/// so callers keep their last cached value rather than blank it.

/// The shape of the GitHub `releases/latest` payload we care about.
interface GitHubReleasePayload {
  tag_name?: string
  assets?: { name?: string; size?: number }[]
}

/// What a caller gets back: the release tag and a human `sizeMB` string, or
/// `null` when there's no `.dmg` asset (honest empty state, never a fake number).
export interface LatestRelease {
  version: string
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

/// Fetches the latest GitHub release for `repo`. Resolves to `{ version, sizeMB }`
/// on success, or `null` on any failure (network error, non-2xx, missing tag,
/// malformed JSON) so callers can keep the cached value.
export async function fetchLatestRelease(
  repo: string = DEFAULT_REPO,
  timeoutMs: number = DEFAULT_TIMEOUT_MS,
): Promise<LatestRelease | null> {
  try {
    const res = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
      headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'vitals-website' },
      signal: AbortSignal.timeout(timeoutMs),
    })
    if (!res.ok) return null
    const json = (await res.json()) as GitHubReleasePayload
    if (!json.tag_name) return null
    const dmg = json.assets?.find((a) => a.name?.endsWith('.dmg'))
    return { version: json.tag_name, sizeMB: bytesToMB(dmg?.size) }
  } catch {
    // Network/parse failure: signal "no update" so the caller keeps its cache.
    return null
  }
}
