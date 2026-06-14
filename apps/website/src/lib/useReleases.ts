import { useCallback, useEffect, useState } from 'react'
import { useAction } from 'convex/react'
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

/// Shared load state machine. `load` resolves to the releases, or `null` on
/// failure (→ error state). It must be referentially stable so the effect
/// re-runs only on retry.
function useReleaseLoader(load: () => Promise<ReleaseSummary[] | null>): ReleasesResult {
  const [nonce, setNonce] = useState(0)
  const [state, setState] = useState<{ status: 'loading' | 'error' | 'ready'; releases: ReleaseSummary[] }>({
    status: 'loading',
    releases: [],
  })

  useEffect(() => {
    let alive = true
    load()
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
  }, [nonce, load])

  // Reset to loading here (not in the effect) and bump the nonce to re-run.
  const retry = useCallback(() => {
    setState({ status: 'loading', releases: [] })
    setNonce((n) => n + 1)
  }, [])
  return { ...state, retry }
}

/// Convex-backed: call the proxy action (one-shot, not reactive). The action
/// throws on a GitHub failure → treat as the error state.
function useReleasesFromConvex(): ReleasesResult {
  const listAction = useAction(api.releases.list)
  const load = useCallback(() => listAction({}).catch(() => null), [listAction])
  return useReleaseLoader(load)
}

/// Fallback: fetch GitHub directly (no backend configured). `fetchReleases` is
/// already stable and returns `null` on failure.
function useReleasesFromGitHub(): ReleasesResult {
  return useReleaseLoader(fetchReleases)
}

/// Every published release, newest first, plus its load state. Bound once at
/// module load to the right source (rules-of-hooks safe).
export const useReleases = convexEnabled ? useReleasesFromConvex : useReleasesFromGitHub
