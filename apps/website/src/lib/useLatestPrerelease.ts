import { useEffect, useState } from 'react'
import { useAction } from 'convex/react'
import { api } from '@convex/_generated/api'
import { fetchLatestPrerelease, type LatestPrerelease } from '@convex/lib/github'
import { convexEnabled } from './convex'

export type { LatestPrerelease }

/// Convex-backed: call the proxy action once on mount for the newest Dev
/// pre-release (the `Vitals-Dev.dmg` feed).
function useLatestPrereleaseFromConvex(): LatestPrerelease | null {
  const latest = useAction(api.releases.latestPrerelease)
  const [release, setRelease] = useState<LatestPrerelease | null>(null)
  useEffect(() => {
    let alive = true
    latest({})
      .then((r) => {
        if (alive) setRelease(r)
      })
      .catch(() => {})
    return () => {
      alive = false
    }
  }, [latest])
  return release
}

/// Fallback: fetch GitHub directly from the browser with the same shared helper
/// the backend uses. Used when no Convex deployment is configured (CI, no backend).
function useLatestPrereleaseFromGitHub(): LatestPrerelease | null {
  const [release, setRelease] = useState<LatestPrerelease | null>(null)
  useEffect(() => {
    let alive = true
    fetchLatestPrerelease().then((r) => {
      if (alive) setRelease(r)
    })
    return () => {
      alive = false
    }
  }, [])
  return release
}

/// Newest Dev pre-release (build number, branch, DMG link, size) for the Dev
/// channel section. Bound once at module load to the right source.
export const useLatestPrerelease = convexEnabled
  ? useLatestPrereleaseFromConvex
  : useLatestPrereleaseFromGitHub
