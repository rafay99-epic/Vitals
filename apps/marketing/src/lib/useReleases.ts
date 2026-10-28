import { useCallback, useEffect, useRef, useState } from 'react'
import { useAction } from 'convex/react'
import { api } from '@convex/_generated/api'
import { fetchReleases, RELEASES_PER_PAGE, type ReleaseSummary } from '@convex/lib/github'
import { convexEnabled } from './convex'

export type { ReleaseSummary }

/// The page needs to tell loading / error / ready apart (empty is `ready` with
/// no rows), offer a retry on error, and page through older releases.
export interface ReleasesResult {
  status: 'loading' | 'error' | 'ready'
  releases: ReleaseSummary[]
  hasMore: boolean
  loadingMore: boolean
  loadMore: () => void
  retry: () => void
}

/// Shared load state machine. `load(page)` resolves to a page of releases, or
/// `null` on failure (→ error state for the first page). It must be referentially
/// stable so the first page loads once on mount. A page that comes back full
/// (`RELEASES_PER_PAGE` rows) means there's probably more.
function useReleaseLoader(load: (page: number) => Promise<ReleaseSummary[] | null>): ReleasesResult {
  const generation = useRef(0)
  const [page, setPage] = useState(1)
  const [hasMore, setHasMore] = useState(false)
  const [loadingMore, setLoadingMore] = useState(false)
  const [state, setState] = useState<{ status: 'loading' | 'error' | 'ready'; releases: ReleaseSummary[] }>({
    status: 'loading',
    releases: [],
  })

  // First page on mount / retry. Each request takes a generation number, so a
  // slow response from a superseded request (or after unmount) is ignored.
  const fetchFirstPage = useCallback(() => {
    generation.current += 1
    const current = generation.current
    load(1)
      .then((list) => {
        if (generation.current !== current) return
        if (list === null) {
          setState({ status: 'error', releases: [] })
          return
        }
        setState({ status: 'ready', releases: list })
        setHasMore(list.length >= RELEASES_PER_PAGE)
      })
      .catch(() => {
        if (generation.current === current) setState({ status: 'error', releases: [] })
      })
  }, [load])

  useEffect(() => {
    fetchFirstPage()
    return () => {
      generation.current += 1
    }
  }, [fetchFirstPage])

  const loadMore = useCallback(() => {
    if (loadingMore) return
    setLoadingMore(true)
    const next = page + 1
    load(next)
      .then((list) => {
        setLoadingMore(false)
        if (!list || list.length === 0) {
          setHasMore(false)
          return
        }
        setState((s) => ({ status: 'ready', releases: [...s.releases, ...list] }))
        setPage(next)
        setHasMore(list.length >= RELEASES_PER_PAGE)
      })
      .catch(() => {
        setLoadingMore(false)
        setHasMore(false)
      })
  }, [page, loadingMore, load])

  // Reset to loading here (an event handler, so setState is fine) and fetch
  // the first page again.
  const retry = useCallback(() => {
    setState({ status: 'loading', releases: [] })
    setPage(1)
    setHasMore(false)
    fetchFirstPage()
  }, [fetchFirstPage])

  return { ...state, hasMore, loadingMore, loadMore, retry }
}

/// Convex-backed: call the proxy action per page (one-shot, not reactive). The
/// action throws on a GitHub failure → treat as the error state.
function useReleasesFromConvex(): ReleasesResult {
  const listAction = useAction(api.releases.list)
  const load = useCallback((page: number) => listAction({ page }).catch(() => null), [listAction])
  return useReleaseLoader(load)
}

/// Fallback: fetch GitHub directly (no backend configured). `fetchReleases`
/// returns `null` on failure.
function useReleasesFromGitHub(): ReleasesResult {
  const load = useCallback((page: number) => fetchReleases({ page }), [])
  return useReleaseLoader(load)
}

/// Every published release, newest first, paged, plus its load state. Bound once
/// at module load to the right source (rules-of-hooks safe).
export const useReleases = convexEnabled ? useReleasesFromConvex : useReleasesFromGitHub
