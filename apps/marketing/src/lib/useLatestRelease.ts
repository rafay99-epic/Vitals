import { useEffect, useState } from 'react'
import { useAction } from 'convex/react'
import { api } from '@convex/_generated/api'
import { fetchLatestRelease, type LatestRelease } from '@convex/lib/github'
import { convexEnabled } from './convex'

export type { LatestRelease }

/// Convex-backed: call the proxy action once on mount (not reactive — a one-shot
/// fetch through the backend).
function useLatestReleaseFromConvex(): LatestRelease | null {
  const latest = useAction(api.releases.latest)
  const [release, setRelease] = useState<LatestRelease | null>(null)
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

/// Fallback: fetch GitHub directly from the browser. Same shared helper the
/// backend uses. Used when no Convex deployment is configured (CI, no backend).
function useLatestReleaseFromGitHub(): LatestRelease | null {
  const [release, setRelease] = useState<LatestRelease | null>(null)
  useEffect(() => {
    let alive = true
    fetchLatestRelease().then((r) => {
      if (alive) setRelease(r)
    })
    return () => {
      alive = false
    }
  }, [])
  return release
}

/// Latest published version + DMG size for the download button. Bound once at
/// module load to the right source (rules-of-hooks safe).
export const useLatestRelease = convexEnabled ? useLatestReleaseFromConvex : useLatestReleaseFromGitHub
