import { useCallback, useEffect, useState } from 'react'
import { useQuery } from 'convex/react'
import { api } from '@convex/_generated/api'
import { fetchReleases, type ReleaseSummary } from '@convex/lib/github'
import { convexEnabled } from './convex'

export type { ReleaseSummary }

/// The page needs to tell loading / error / ready apart (empty is `ready` with
/// no rows), and offer a retry on error.
export interface ReleasesResult {
  status: 'loading' | 'error' | 'ready'
  releases: ReleaseSummary[]
  retry: () => void
}

/// Convex-backed: reactive read of the cached list. `undefined` means the first
/// load is still in flight. A query error throws up to the route's error
/// boundary (rare, infra-level), so this path doesn't surface `error` inline.
function useReleasesFromConvex(): ReleasesResult {
  const data = useQuery(api.releases.list, {})
  return {
    status: data === undefined ? 'loading' : 'ready',
    releases: data ?? [],
    retry: () => window.location.reload(),
  }
}

/// Fallback: fetch straight from GitHub (same `fetchReleases` helper the backend
/// uses). Surfaces a real `error` state, and `retry` re-runs the fetch.
function useReleasesFromGitHub(): ReleasesResult {
  const [nonce, setNonce] = useState(0)
  const [state, setState] = useState<{ status: 'loading' | 'error' | 'ready'; releases: ReleaseSummary[] }>({
    status: 'loading',
    releases: [],
  })

  useEffect(() => {
    let alive = true
    fetchReleases()
      .then((list) => {
        if (!alive) return
        setState(list === null ? { status: 'error', releases: [] } : { status: 'ready', releases: list })
      })
      .catch(() => {
        if (alive) setState({ status: 'error', releases: [] })
      })
    return () => {
      alive = false
    }
  }, [nonce])

  // Reset to loading here (not in the effect) and bump the nonce to re-fetch.
  const retry = useCallback(() => {
    setState({ status: 'loading', releases: [] })
    setNonce((n) => n + 1)
  }, [])
  return { ...state, retry }
}

/// Every published release, newest first, plus its load state. Bound once at
/// module load to the right source (rules-of-hooks safe).
export const useReleases = convexEnabled ? useReleasesFromConvex : useReleasesFromGitHub
