import { useEffect, useState } from 'react'
import { useQuery } from 'convex/react'
import { api } from '@vitals/backend/api'
import { REPO } from './links'
import { convexEnabled } from './convex'

export interface LatestRelease {
  version: string
  sizeMB: string | null
}

/// Convex-backed: a reactive read of the release the backend caches server-side.
/// When the cron refreshes it, this updates with no extra fetch.
function useLatestReleaseFromConvex(): LatestRelease | null {
  return useQuery(api.releases.get, {}) ?? null
}

/// Fallback: fetch GitHub directly from the browser. Used when no Convex
/// deployment is configured (CI builds, or running the site without a backend),
/// so the badge still shows the real latest version.
function useLatestReleaseFromGitHub(): LatestRelease | null {
  const [release, setRelease] = useState<LatestRelease | null>(null)
  useEffect(() => {
    fetch(`https://api.github.com/repos/${REPO}/releases/latest`)
      .then((response) => (response.ok ? response.json() : null))
      .then((json) => {
        if (!json?.tag_name) return
        const dmg = (json.assets as { name: string; size: number }[] | undefined)?.find((a) =>
          a.name.endsWith('.dmg'),
        )
        setRelease({
          version: json.tag_name,
          sizeMB: dmg ? (dmg.size / 1048576).toFixed(1) + ' MB' : null,
        })
      })
      .catch(() => {})
  }, [])
  return release
}

/// Latest published version + DMG size for the download button. Bound once at
/// module load to the right source — the choice never changes between renders,
/// so the same hook runs every time (rules-of-hooks safe).
export const useLatestRelease = convexEnabled
  ? useLatestReleaseFromConvex
  : useLatestReleaseFromGitHub
