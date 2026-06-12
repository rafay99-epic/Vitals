import { useEffect, useState } from 'react'
import { REPO } from './links'

export interface LatestRelease {
  version: string
  sizeMB: string | null
}

/// Latest published version + DMG size, straight from GitHub Releases —
/// the download button's /latest/download/ URL always matches it.
export function useLatestRelease(): LatestRelease | null {
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
