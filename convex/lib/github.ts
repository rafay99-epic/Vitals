/// Reusable, Convex-free GitHub release fetchers. No Convex imports — just
/// `fetch` + parse — so the Convex actions and the website's direct-fetch
/// fallback share one parser. Returns `null` on any failure (network, non-2xx,
/// malformed) so the caller can show an empty/error state.

/// The shape of a GitHub release payload we care about.
interface GitHubReleasePayload {
  tag_name?: string
  name?: string | null
  html_url?: string
  published_at?: string | null
  draft?: boolean
  prerelease?: boolean
  body?: string | null
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
  body: string
  prerelease: boolean
}

/// The latest release as the download badge consumes it.
export interface LatestRelease {
  version: string
  sizeMB: string | null
}

/// The latest Nightly pre-release (a GitHub *prerelease* carrying a
/// `Vitals-Nightly.dmg` asset) as the marketing site consumes it. `buildNumber`
/// is parsed from the release name `Vitals Nightly · build <n>`; `branch` is
/// parsed only from legacy `Vitals Dev · <branch> · build <n>` titles and is
/// null for new Nightly releases. Any field is null when it can't be read
/// honestly.
export type LatestPrerelease = {
  tag: string
  name: string
  branch: string | null
  buildNumber: number | null
  dmgUrl: string | null
  sizeMB: string | null
  publishedAt: string
}

/// `token` lifts GitHub's unauthenticated 60-req/hour-per-IP limit to 5,000.
/// Only the server-side Convex actions pass it (from `GITHUB_TOKEN`); the
/// browser fallback never does — a token must not reach client code.
export interface FetchOptions {
  repo?: string
  timeoutMs?: number
  token?: string
  page?: number
}

const DEFAULT_REPO = 'rafay99-epic/Vitals'
const DEFAULT_TIMEOUT_MS = 10_000
const BYTES_PER_MB = 1_048_576

/// How many releases `fetchReleases` requests per page. The website imports this
/// to detect "has more" (a full page means there may be another).
export const RELEASES_PER_PAGE = 15

function headers(token?: string): Record<string, string> {
  const h: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'vitals-website',
  }
  if (token) h.Authorization = `Bearer ${token}`
  return h
}

/// Shared GET against the GitHub API with the common auth header + abort timeout.
/// Returns the parsed JSON, or `null` on any failure (network error, non-2xx).
/// Callers add their own shape validation.
async function githubGet(path: string, opts: FetchOptions): Promise<unknown | null> {
  const { repo = DEFAULT_REPO, timeoutMs = DEFAULT_TIMEOUT_MS, token } = opts
  const res = await fetch(`https://api.github.com/repos/${repo}/${path}`, {
    headers: headers(token),
    signal: AbortSignal.timeout(timeoutMs),
  })
  if (!res.ok) return null
  return (await res.json()) as unknown
}

/// Formats a byte count as a `"12.3 MB"` string. Returns `null` for missing or
/// non-positive sizes so the badge stays honest.
export function bytesToMB(bytes: number | undefined): string | null {
  if (!bytes || bytes <= 0) return null
  return (bytes / BYTES_PER_MB).toFixed(1) + ' MB'
}

/// Fetches the latest published release for the download badge, or `null` on
/// any failure (so the badge shows no version rather than a fake one).
export async function fetchLatestRelease(opts: FetchOptions = {}): Promise<LatestRelease | null> {
  try {
    const json = (await githubGet('releases/latest', opts)) as GitHubReleasePayload | null
    if (!json || !json.tag_name) return null
    const dmg = json.assets?.find((a) => a.name?.endsWith('.dmg'))
    return { version: json.tag_name, sizeMB: bytesToMB(dmg?.size) }
  } catch {
    return null
  }
}

/// Fetches one page of the release list for `repo` (`RELEASES_PER_PAGE` items,
/// `options.page` defaulting to 1). Resolves to a newest-first array of
/// `ReleaseSummary`, or `null` on any failure (network error, non-2xx, non-array
/// body) so the caller can show an error state. Drafts and tag-less releases are
/// filtered out; prereleases (Nightly builds) are KEPT and flagged via `prerelease`.
export async function fetchReleases(opts: FetchOptions = {}): Promise<ReleaseSummary[] | null> {
  try {
    const page = opts.page ?? 1
    const json = await githubGet(`releases?per_page=${RELEASES_PER_PAGE}&page=${page}`, opts)
    if (!Array.isArray(json)) return null

    const summaries: ReleaseSummary[] = []
    for (const raw of json as GitHubReleasePayload[]) {
      if (raw.draft || !raw.tag_name) continue
      const dmg = raw.assets?.find((a) => a.name?.endsWith('.dmg'))
      summaries.push({
        tag: raw.tag_name,
        name: raw.name && raw.name.length > 0 ? raw.name : raw.tag_name,
        publishedAt: raw.published_at ? Date.parse(raw.published_at) : 0,
        url: raw.html_url ?? '',
        dmgUrl: dmg?.browser_download_url ?? null,
        sizeMB: bytesToMB(dmg?.size),
        body: raw.body ?? '',
        prerelease: raw.prerelease ?? false,
      })
    }
    // Newest first — the page lists in this order.
    summaries.sort((a, b) => b.publishedAt - a.publishedAt)
    return summaries
  } catch {
    return null
  }
}

/// The exact asset name a Nightly pre-release ships. A release may carry both
/// `Vitals.dmg` and `Vitals-Nightly.dmg`, so we match this name exactly (never
/// `.endsWith('.dmg')`). Hard cut: old `Vitals-Dev.dmg` assets are intentionally
/// ignored.
const NIGHTLY_DMG_NAME = 'Vitals-Nightly.dmg'

/// Fetches the latest Nightly *pre-release* — the inverse of the public fetchers,
/// which deliberately drop prereleases. Scans the (newest-first) release list
/// and returns the FIRST non-draft prerelease carrying an asset named exactly
/// `Vitals-Nightly.dmg`, parsing `buildNumber` from its name
/// `Vitals Nightly · build <n>`. `branch` is parsed only from legacy
/// `Vitals Dev · <branch> · build <n>` titles (null for new Nightly releases).
/// Returns `null` on any failure or when no matching prerelease exists, so the
/// site degrades gracefully (never throws).
export async function fetchLatestPrerelease(options: FetchOptions = {}): Promise<LatestPrerelease | null> {
  try {
    const json = await githubGet('releases?per_page=30', options)
    if (!Array.isArray(json)) return null

    for (const raw of json as GitHubReleasePayload[]) {
      if (!raw.prerelease || raw.draft || !raw.tag_name) continue
      const dmg = raw.assets?.find((a) => a.name === NIGHTLY_DMG_NAME)
      if (!dmg) continue

      const name = raw.name && raw.name.length > 0 ? raw.name : raw.tag_name
      const buildMatch = name.match(/build (\d+)/)
      const buildNumber = buildMatch ? Number(buildMatch[1]) : null
      const branchMatch = name.match(/^Vitals (?:Dev|Nightly) · (.+?) · build \d+/)
      const branch = branchMatch ? branchMatch[1] : null

      return {
        tag: raw.tag_name,
        name,
        branch,
        buildNumber,
        dmgUrl: dmg.browser_download_url ?? null,
        sizeMB: bytesToMB(dmg.size),
        publishedAt: raw.published_at ?? '',
      }
    }
    return null
  } catch {
    return null
  }
}
