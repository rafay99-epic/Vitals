import type { ReactNode } from 'react'
import { LogoMark } from '../components/icons'
import { COMPANY, DEVELOPER, DEVELOPER_URL, REPO_URL } from '../lib/links'

/// Shared shell for the standalone status pages — Not Found (404) and the
/// error-boundary fallback. Same materials and type treatment as the landing
/// and legal pages, but a single centred column so a short message reads as
/// deliberate, not broken. Honesty applies here too: these pages state plainly
/// what happened and never fake a reading.

/// A flat heartbeat — the brand's pulse with no signal. On a hardware monitor a
/// flatline is the truthful glyph for "nothing to read here".
function Flatline({ width = 132, color = 'rgba(255,69,58,0.85)' }: { width?: number; color?: string }) {
  return (
    <svg width={width} height={width * 0.3} viewBox="0 0 220 66" fill="none" aria-hidden>
      <polyline
        points="0,33 96,33 104,33 110,33 118,33 220,33"
        fill="none"
        stroke={color}
        strokeWidth={2.4}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx="110" cy="33" r="3.4" fill={color} />
    </svg>
  )
}

export function StatusScreen({
  eyebrow,
  title,
  message,
  actions,
}: {
  eyebrow?: string
  title: string
  message: ReactNode
  actions: ReactNode
}) {
  return (
    <div
      style={{
        position: 'relative',
        minHeight: '100vh',
        width: '100%',
        display: 'flex',
        flexDirection: 'column',
        overflowX: 'hidden',
        background:
          'radial-gradient(1100px 620px at 50% -8%, rgba(10,132,255,0.16), transparent 60%), radial-gradient(900px 520px at 88% 18%, rgba(255,159,10,0.10), transparent 55%), #060608',
      }}
    >
      <header style={{ position: 'fixed', top: 0, left: 0, right: 0, zIndex: 100, display: 'flex', justifyContent: 'center', padding: '14px 20px' }}>
        <nav
          style={{
            width: '100%',
            maxWidth: 760,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            padding: '9px 12px 9px 16px',
            background: 'rgba(20,20,23,0.6)',
            backdropFilter: 'blur(28px) saturate(180%)',
            WebkitBackdropFilter: 'blur(28px) saturate(180%)',
            border: '1px solid rgba(255,255,255,0.09)',
            borderRadius: 17,
            boxShadow: '0 10px 40px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.06)',
          }}
        >
          <a href="/" style={{ display: 'flex', alignItems: 'center', gap: 9, textDecoration: 'none', color: '#f5f5f7' }}>
            <LogoMark box={26} radius={7} icon={17} />
            <span style={{ fontSize: 15, fontWeight: 600, letterSpacing: '-0.01em' }}>Vitals</span>
          </a>
          <a
            href="/"
            style={{ fontSize: 13, color: 'rgba(235,235,245,0.62)', textDecoration: 'none', padding: '7px 12px', borderRadius: 9, border: '1px solid rgba(255,255,255,0.1)' }}
          >
            ← Back to Vitals
          </a>
        </nav>
      </header>

      <main
        className="px-6 pt-[120px] pb-16"
        style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center' }}
      >
        <Flatline />
        {eyebrow ? (
          <p
            style={{
              fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
              fontSize: 13,
              letterSpacing: '0.18em',
              color: 'rgba(235,235,245,0.4)',
              margin: '26px 0 0',
            }}
          >
            {eyebrow}
          </p>
        ) : null}
        <h1
          className="text-[30px] md:text-[40px]"
          style={{ fontWeight: 670, letterSpacing: '-0.03em', lineHeight: 1.1, margin: '12px 0 0', maxWidth: 560 }}
        >
          {title}
        </h1>
        <p style={{ fontSize: 16, lineHeight: 1.6, color: 'rgba(235,235,245,0.6)', margin: '16px 0 0', maxWidth: 480 }}>{message}</p>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, justifyContent: 'center', margin: '30px 0 0' }}>{actions}</div>
      </main>

      <footer style={{ padding: '0 24px 36px', textAlign: 'center', fontSize: 12.5, color: 'rgba(235,235,245,0.38)' }}>
        © {new Date().getFullYear()} {COMPANY} · Developed by{' '}
        <a href={DEVELOPER_URL} target="_blank" rel="noreferrer" style={{ color: 'rgba(235,235,245,0.5)', textDecoration: 'none' }}>
          {DEVELOPER} — rafay99.com
        </a>{' '}
        ·{' '}
        <a href={REPO_URL} target="_blank" rel="noreferrer" style={{ color: 'rgba(235,235,245,0.5)', textDecoration: 'none' }}>
          GitHub
        </a>
      </footer>
    </div>
  )
}
