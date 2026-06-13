import type { CSSProperties } from 'react'
import { LegalLayout } from './LegalLayout'
import { useReleases, type ReleaseSummary } from '../lib/useReleases'
import { useTitle } from '../lib/useTitle'
import { REPO_URL } from '../lib/links'

/// The `/releases` page: every published version of Vitals, newest first,
/// straight from the backend's cached GitHub release list (with a direct-GitHub
/// fallback). Each row links to its DMG and to the GitHub release notes — no
/// fabricated data; a release with no `.dmg` simply shows no download.
export default function Releases() {
  useTitle('Releases — Vitals')
  const releases = useReleases()

  return (
    <LegalLayout title="Releases">
      <p style={{ fontSize: 15, lineHeight: 1.6, color: 'rgba(235,235,245,0.62)', margin: '0 0 32px' }}>
        Every published version of Vitals, newest first. Each ships as a signed DMG that
        auto-updates itself.
      </p>

      {releases === null ? (
        <p style={{ fontSize: 14, color: 'rgba(235,235,245,0.45)' }}>Loading releases…</p>
      ) : releases.length === 0 ? (
        <p style={{ fontSize: 14, color: 'rgba(235,235,245,0.45)' }}>
          No releases yet.{' '}
          <a href={`${REPO_URL}/releases`} target="_blank" rel="noreferrer" style={{ color: '#56AFFF', textDecoration: 'none' }}>
            Check GitHub →
          </a>
        </p>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {releases.map((release) => (
            <ReleaseRow key={release.tag} release={release} />
          ))}
        </div>
      )}
    </LegalLayout>
  )
}

const card: CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  flexWrap: 'wrap',
  gap: 14,
  padding: '16px 18px',
  borderRadius: 12,
  background: 'rgba(255,255,255,0.03)',
  border: '1px solid rgba(255,255,255,0.08)',
}

function ReleaseRow({ release }: { release: ReleaseSummary }) {
  const date =
    release.publishedAt > 0
      ? new Date(release.publishedAt).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' })
      : null

  return (
    <div style={card}>
      <div style={{ minWidth: 0 }}>
        <div
          style={{ fontSize: 16, fontWeight: 600, letterSpacing: '-0.01em', color: '#f5f5f7', fontVariantNumeric: 'tabular-nums' }}
        >
          {release.name}
        </div>
        <div style={{ fontSize: 12.5, color: 'rgba(235,235,245,0.45)', marginTop: 3 }}>
          {[date, release.sizeMB].filter(Boolean).join(' · ') || 'No DMG'}
        </div>
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <a
          href={release.url}
          target="_blank"
          rel="noreferrer"
          style={{ fontSize: 13, color: 'rgba(235,235,245,0.62)', textDecoration: 'none', padding: '8px 12px', borderRadius: 9, border: '1px solid rgba(255,255,255,0.12)' }}
        >
          Notes
        </a>
        {release.dmgUrl ? (
          <a
            href={release.dmgUrl}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 7,
              fontSize: 13,
              fontWeight: 560,
              color: '#fff',
              textDecoration: 'none',
              padding: '8px 14px',
              borderRadius: 9,
              background: 'linear-gradient(180deg, #1a8cff, #0a72e8)',
              boxShadow: '0 4px 14px rgba(10,132,255,0.35), inset 0 1px 0 rgba(255,255,255,0.22)',
            }}
          >
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
              <path d="M12 3v11m0 0l-4-4m4 4l4-4M5 19h14" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            Download
          </a>
        ) : null}
      </div>
    </div>
  )
}
