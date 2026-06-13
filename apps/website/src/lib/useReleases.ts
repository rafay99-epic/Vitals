import { useEffect, useState } from 'react'
import { useQuery } from 'convex/react'
import { api } from '@convex/_generated/api'
import { fetchReleases, type ReleaseSummary } from '@convex/lib/github'
import { convexEnabled } from './convex'

export type { ReleaseSummary }

/// Convex-backed: a reactive read of the cached release list. When CI refreshes
/// it on a new release, this updates with no extra fetch.
function useReleasesFromConvex(): ReleaseSummary[] | null {
  return useQuery(api.releases.list, {}) ?? null
}

/// Fallback: fetch the list straight from GitHub. Reuses the SAME Convex-free
/// `fetchReleases` helper the backend uses, so there's one parser, not two. Used
/// when no Convex deployment is configured (CI builds, or no backend).
function useReleasesFromGitHub(): ReleaseSummary[] | null {
  const [releases, setReleases] = useState<ReleaseSummary[] | null>(null)
  useEffect(() => {
    let alive = true
    fetchReleases().then((list) => {
      if (alive && list !== null) setReleases(list)
    })
    return () => {
      alive = false
    }
  }, [])
  return releases
}

/// Every published release, newest first. Bound once at module load to the right
/// source — the choice never changes between renders (rules-of-hooks safe).
export const useReleases = convexEnabled ? useReleasesFromConvex : useReleasesFromGitHub
