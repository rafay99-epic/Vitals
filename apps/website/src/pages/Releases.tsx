import { useState, type CSSProperties, type ReactNode } from 'react'
import { LegalLayout } from './LegalLayout'
import { useReleases, type ReleaseSummary } from '../lib/useReleases'
import { useTitle } from '../lib/useTitle'
import { REPO_URL } from '../lib/links'

/// Style objects can carry CSS custom properties (e.g. the per-row stagger
/// index) — React allows it, TS's CSSProperties doesn't, so widen the type.
type Style = CSSProperties & Record<string, string | number>

const AMBER = '#FF9F0A'

/// The `/releases` page: every published version of Vitals, newest first, from
/// the backend's paged release list (with a direct-GitHub fallback). Rows expand
/// to show their notes inline; "Load more" pages through older releases. Loading
/// shows a shimmering skeleton; failures show a retry; an empty list says so.
export default function Releases() {
  useTitle('Releases — Vitals')
  const { status, releases, hasMore, loadingMore, loadMore, retry } = useReleases()

  return (
    <LegalLayout title="Releases">
      <p style={{ fontSize: 15, lineHeight: 1.6, color: 'rgba(235,235,245,0.62)', margin: '0 0 32px' }}>
        Every published version of Vitals, newest first. Stable releases auto-update themselves;{' '}
        <span style={{ color: AMBER }}>pre-releases</span> are unsigned Nightly builds. Expand any row to read its notes.
      </p>

      {status === 'loading' ? (
        <SkeletonList />
      ) : status === 'error' ? (
        <ErrorState onRetry={retry} />
      ) : releases.length === 0 ? (
        <EmptyState />
      ) : (
        <>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {releases.map((release, i) => (
              <ReleaseRow key={release.tag} release={release} index={i} />
            ))}
          </div>
          {hasMore && (
            <div style={{ display: 'flex', justifyContent: 'center', marginTop: 22 }}>
              <button
                type="button"
                onClick={loadMore}
                disabled={loadingMore}
                style={{ ...ghostButton, cursor: loadingMore ? 'default' : 'pointer', opacity: loadingMore ? 0.6 : 1 }}
              >
                {loadingMore ? 'Loading…' : 'Load older releases'}
              </button>
            </div>
          )}
        </>
      )}
    </LegalLayout>
  )
}

// MARK: - Rows

const card: CSSProperties = {
  borderRadius: 12,
  background: 'rgba(255,255,255,0.03)',
  border: '1px solid rgba(255,255,255,0.08)',
  overflow: 'hidden',
}

function ReleaseRow({ release, index }: { release: ReleaseSummary; index: number }) {
  const [open, setOpen] = useState(false)
  const date =
    release.publishedAt > 0
      ? new Date(release.publishedAt).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' })
      : null

  // Cap the stagger so the tail of a long list doesn't wait seconds.
  const rowStyle: Style = { ...card, '--vt-i': Math.min(index, 12) }

  return (
    <div className="vt-release-row" style={rowStyle}>
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          flexWrap: 'wrap',
          gap: 14,
          padding: '15px 16px 15px 8px',
        }}
      >
        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          aria-expanded={open}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            minWidth: 0,
            flex: '1 1 auto',
            background: 'transparent',
            border: 'none',
            padding: '4px 6px',
            cursor: 'pointer',
            textAlign: 'left',
            color: 'inherit',
          }}
        >
          <Chevron open={open} />
          <span style={{ minWidth: 0 }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <span
                style={{
                  fontSize: 16,
                  fontWeight: 600,
                  letterSpacing: '-0.01em',
                  color: '#f5f5f7',
                  fontVariantNumeric: 'tabular-nums',
                }}
              >
                {release.name}
              </span>
              {release.prerelease && (
                <span
                  style={{
                    fontSize: 10,
                    fontWeight: 800,
                    letterSpacing: '0.06em',
                    color: AMBER,
                    padding: '2px 7px',
                    borderRadius: 999,
                    background: 'rgba(255,159,10,0.13)',
                    border: '1px solid rgba(255,159,10,0.35)',
                  }}
                >
                  PRE-RELEASE
                </span>
              )}
            </span>
            <span style={{ display: 'block', fontSize: 12.5, color: 'rgba(235,235,245,0.45)', marginTop: 3 }}>
              {[date, release.sizeMB].filter(Boolean).join(' · ') || 'No DMG'}
            </span>
          </span>
        </button>

        {release.dmgUrl ? (
          <a href={release.dmgUrl} style={release.prerelease ? nightlyButton : primaryButton}>
            <DownloadGlyph tint={release.prerelease ? AMBER : '#fff'} />
            Download
          </a>
        ) : null}
      </div>

      {/* Smooth open/close: the outer grid animates 0fr→1fr (height) while the
          panel fades in. No JS height measurement needed. */}
      <div
        style={{
          display: 'grid',
          gridTemplateRows: open ? '1fr' : '0fr',
          transition: 'grid-template-rows 0.28s cubic-bezier(0.4, 0, 0.2, 1)',
        }}
      >
        <div style={{ overflow: 'hidden', minHeight: 0 }}>
          <div
            style={{
              borderTop: '1px solid rgba(255,255,255,0.07)',
              padding: '14px 18px 18px 30px',
              background: 'rgba(0,0,0,0.15)',
              opacity: open ? 1 : 0,
              transition: 'opacity 0.28s ease',
            }}
          >
            <ReleaseNotes body={release.body} />
            <a
              href={release.url}
              target="_blank"
              rel="noreferrer"
              style={{ display: 'inline-block', marginTop: 14, fontSize: 12.5, color: 'rgba(235,235,245,0.5)', textDecoration: 'none' }}
            >
              View on GitHub →
            </a>
          </div>
        </div>
      </div>
    </div>
  )
}

// MARK: - Notes (markdown-lite)

const linkStyle: CSSProperties = { color: '#4aa3ff', textDecoration: 'none' }
const codeStyle: CSSProperties = {
  fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
  fontSize: '0.86em',
  padding: '1px 5px',
  borderRadius: 5,
  background: 'rgba(255,255,255,0.08)',
}

/// Inline markdown: **bold**, `code`, [text](url), and bare URLs → links.
function renderInline(text: string, key: string): ReactNode[] {
  const nodes: ReactNode[] = []
  const re = /(\*\*([^*]+)\*\*)|(`([^`]+)`)|(\[([^\]]+)\]\((https?:\/\/[^\s)]+)\))|(https?:\/\/[^\s)]+)/g
  let last = 0
  let m: RegExpExecArray | null
  let i = 0
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) nodes.push(text.slice(last, m.index))
    if (m[2] != null) {
      nodes.push(
        <strong key={`${key}-b${i}`} style={{ color: '#f5f5f7', fontWeight: 600 }}>
          {m[2]}
        </strong>,
      )
    } else if (m[4] != null) {
      nodes.push(
        <code key={`${key}-c${i}`} style={codeStyle}>
          {m[4]}
        </code>,
      )
    } else if (m[6] != null) {
      nodes.push(
        <a key={`${key}-l${i}`} href={m[7]} target="_blank" rel="noreferrer" style={linkStyle}>
          {m[6]}
        </a>,
      )
    } else if (m[8] != null) {
      nodes.push(
        <a key={`${key}-u${i}`} href={m[8]} target="_blank" rel="noreferrer" style={linkStyle}>
          {m[8].replace(/^https?:\/\//, '').replace(/\/$/, '')}
        </a>,
      )
    }
    last = re.lastIndex
    i++
  }
  if (last < text.length) nodes.push(text.slice(last))
  return nodes
}

/// Block-level: headings, bullet lists, paragraphs. Just enough to render
/// GitHub's auto-generated notes and our Nightly-build notes cleanly.
function ReleaseNotes({ body }: { body: string }) {
  const text = (body ?? '').trim()
  if (!text) {
    return <p style={{ fontSize: 13.5, color: 'rgba(235,235,245,0.4)', margin: 0 }}>No notes for this release.</p>
  }

  const blocks: ReactNode[] = []
  let bullets: ReactNode[] = []
  const flush = () => {
    if (bullets.length) {
      blocks.push(
        <ul key={`ul-${blocks.length}`} style={{ margin: '4px 0 10px', paddingLeft: 18, display: 'flex', flexDirection: 'column', gap: 4 }}>
          {bullets}
        </ul>,
      )
      bullets = []
    }
  }

  text.split('\n').forEach((raw, idx) => {
    const line = raw.trim()
    if (!line) {
      flush()
      return
    }
    if (/^#{1,6}\s/.test(line)) {
      flush()
      blocks.push(
        <div key={`h-${idx}`} style={{ fontSize: 13, fontWeight: 700, color: '#f5f5f7', margin: blocks.length ? '12px 0 4px' : '0 0 4px', letterSpacing: '0.01em' }}>
          {renderInline(line.replace(/^#{1,6}\s/, ''), `h${idx}`)}
        </div>,
      )
    } else if (/^[*-]\s/.test(line)) {
      bullets.push(
        <li key={`li-${idx}`} style={{ fontSize: 13, lineHeight: 1.55, color: 'rgba(235,235,245,0.66)' }}>
          {renderInline(line.replace(/^[*-]\s/, ''), `li${idx}`)}
        </li>,
      )
    } else {
      flush()
      blocks.push(
        <p key={`p-${idx}`} style={{ fontSize: 13, lineHeight: 1.6, color: 'rgba(235,235,245,0.66)', margin: '0 0 8px' }}>
          {renderInline(line, `p${idx}`)}
        </p>,
      )
    }
  })
  flush()

  return <div>{blocks}</div>
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
    <div style={{ ...card, padding: '16px 18px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
        <Bar w={150} h={15} />
        <Bar w={96} h={11} />
      </div>
      <Bar w={104} h={31} />
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
  flexShrink: 0,
}
const nightlyButton: CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 7,
  fontSize: 13,
  fontWeight: 560,
  color: AMBER,
  textDecoration: 'none',
  padding: '8px 14px',
  borderRadius: 9,
  background: 'rgba(191,90,242,0.1)',
  border: '1px solid rgba(191,90,242,0.32)',
  flexShrink: 0,
}
const ghostButton: CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  fontSize: 13,
  color: 'rgba(235,235,245,0.62)',
  textDecoration: 'none',
  padding: '8px 14px',
  borderRadius: 9,
  border: '1px solid rgba(255,255,255,0.12)',
  background: 'transparent',
}

function Chevron({ open }: { open: boolean }) {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      style={{ flexShrink: 0, transform: open ? 'rotate(90deg)' : 'none', transition: 'transform 0.18s ease', opacity: 0.55 }}
    >
      <path d="M9 6l6 6-6 6" stroke="#f5f5f7" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function DownloadGlyph({ tint = '#fff' }: { tint?: string }) {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
      <path d="M12 3v11m0 0l-4-4m4 4l4-4M5 19h14" stroke={tint} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
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
