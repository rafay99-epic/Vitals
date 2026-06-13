import type { CSSProperties } from 'react'
import { LegalLayout } from './LegalLayout'
import { useReleases, type ReleaseSummary } from '../lib/useReleases'
import { useTitle } from '../lib/useTitle'
import { REPO_URL } from '../lib/links'

/// Style objects can carry CSS custom properties (e.g. the per-row stagger
/// index) — React allows it, TS's CSSProperties doesn't, so widen the type.
type Style = CSSProperties & Record<string, string | number>

/// The `/releases` page: every published version of Vitals, newest first, from
/// the backend's cached release list (with a direct-GitHub fallback). Loading
/// shows a shimmering skeleton; failures show a retry; an empty cache says so —
/// no fabricated data. Rows fade in, staggered, as the data arrives.
export default function Releases() {
  useTitle('Releases — Vitals')
  const { status, releases, retry } = useReleases()

  return (
    <LegalLayout title="Releases">
      <p style={{ fontSize: 15, lineHeight: 1.6, color: 'rgba(235,235,245,0.62)', margin: '0 0 32px' }}>
        Every published version of Vitals, newest first. Each ships as a signed DMG that
        auto-updates itself.
      </p>

      {status === 'loading' ? (
        <SkeletonList />
      ) : status === 'error' ? (
        <ErrorState onRetry={retry} />
      ) : releases.length === 0 ? (
        <EmptyState />
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {releases.map((release, i) => (
            <ReleaseRow key={release.tag} release={release} index={i} />
          ))}
        </div>
      )}
    </LegalLayout>
  )
}

// MARK: - Cards

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

function ReleaseRow({ release, index }: { release: ReleaseSummary; index: number }) {
  const date =
    release.publishedAt > 0
      ? new Date(release.publishedAt).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' })
      : null

  // Cap the stagger so the tail of a long list doesn't wait seconds.
  const rowStyle: Style = { ...card, '--vt-i': Math.min(index, 12) }

  return (
    <div className="vt-release-row" style={rowStyle}>
      <div style={{ minWidth: 0 }}>
        <div style={{ fontSize: 16, fontWeight: 600, letterSpacing: '-0.01em', color: '#f5f5f7', fontVariantNumeric: 'tabular-nums' }}>
          {release.name}
        </div>
        <div style={{ fontSize: 12.5, color: 'rgba(235,235,245,0.45)', marginTop: 3 }}>
          {[date, release.sizeMB].filter(Boolean).join(' · ') || 'No DMG'}
        </div>
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <a href={release.url} target="_blank" rel="noreferrer" style={ghostButton}>
          Notes
        </a>
        {release.dmgUrl ? (
          <a href={release.dmgUrl} style={primaryButton}>
            <DownloadGlyph />
            Download
          </a>
        ) : null}
      </div>
    </div>
  )
}

// MARK: - States

function SkeletonList() {
  return (
    <div className="vt-appear" style={{ display: 'flex', flexDirection: 'column', gap: 10 }} aria-hidden>
      {Array.from({ length: 6 }, (_, i) => (
        <SkeletonRow key={i} />
      ))}
    </div>
  )
}

function SkeletonRow() {
  return (
    <div style={card}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
        <Bar w={150} h={15} />
        <Bar w={96} h={11} />
      </div>
      <div style={{ display: 'flex', gap: 8 }}>
        <Bar w={58} h={31} />
        <Bar w={104} h={31} />
      </div>
    </div>
  )
}

function Bar({ w, h }: { w: number; h: number }) {
  return (
    <div
      className="vt-skeleton-sheen"
      style={{ width: w, height: h, borderRadius: 7, background: 'rgba(255,255,255,0.06)' }}
    />
  )
}

function ErrorState({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="vt-appear" style={stateBox}>
      <StateGlyph tint="rgba(255,69,58,0.9)" path="M12 8v5M12 16.5v.5M10.3 4.3 2.7 18a2 2 0 0 0 1.7 3h15.2a2 2 0 0 0 1.7-3L13.7 4.3a2 2 0 0 0-3.4 0Z" />
      <p style={stateTitle}>Couldn’t load releases</p>
      <p style={stateMessage}>Something went wrong reaching the release list. It may be a temporary hiccup.</p>
      <div style={{ display: 'flex', gap: 10, justifyContent: 'center', flexWrap: 'wrap' }}>
        <button type="button" onClick={onRetry} style={{ ...primaryButton, border: 'none', cursor: 'pointer' }}>
          Try again
        </button>
        <a href={`${REPO_URL}/releases`} target="_blank" rel="noreferrer" style={ghostButton}>
          View on GitHub →
        </a>
      </div>
    </div>
  )
}

function EmptyState() {
  return (
    <div className="vt-appear" style={stateBox}>
      <StateGlyph tint="rgba(235,235,245,0.4)" path="M4 7h16M4 12h16M4 17h10" />
      <p style={stateTitle}>No releases yet</p>
      <p style={stateMessage}>There aren’t any published releases to show right now.</p>
      <a href={`${REPO_URL}/releases`} target="_blank" rel="noreferrer" style={ghostButton}>
        Check GitHub →
      </a>
    </div>
  )
}

// MARK: - Shared bits

const stateBox: CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  alignItems: 'center',
  textAlign: 'center',
  gap: 6,
  padding: '44px 20px',
  borderRadius: 12,
  background: 'rgba(255,255,255,0.02)',
  border: '1px solid rgba(255,255,255,0.07)',
}
const stateTitle: CSSProperties = { fontSize: 16, fontWeight: 600, color: '#f5f5f7', margin: '8px 0 0' }
const stateMessage: CSSProperties = { fontSize: 13.5, color: 'rgba(235,235,245,0.5)', margin: '0 0 8px', maxWidth: 360 }

const primaryButton: CSSProperties = {
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
}
const ghostButton: CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  fontSize: 13,
  color: 'rgba(235,235,245,0.62)',
  textDecoration: 'none',
  padding: '8px 12px',
  borderRadius: 9,
  border: '1px solid rgba(255,255,255,0.12)',
  background: 'transparent',
}

function DownloadGlyph() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
      <path d="M12 3v11m0 0l-4-4m4 4l4-4M5 19h14" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function StateGlyph({ tint, path }: { tint: string; path: string }) {
  return (
    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke={tint} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d={path} />
    </svg>
  )
}
