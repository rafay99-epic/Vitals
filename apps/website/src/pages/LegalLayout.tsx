import type { ReactNode } from 'react'
import { Link } from '@tanstack/react-router'
import { LogoMark } from '../components/icons'
import { COMPANY, DEVELOPER, DEVELOPER_URL, REPO_URL } from '../lib/links'

/// Shared shell for sub-pages (Terms, Privacy, Releases) — same materials and
/// type treatment as the landing page, single column. `updated` is optional;
/// pages that aren't dated (Releases) omit it.
export function LegalLayout({ title, updated, children }: { title: string; updated?: string; children: ReactNode }) {
  return (
    <div
      style={{
        position: 'relative',
        minHeight: '100vh',
        width: '100%',
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
          <Link to="/" style={{ display: 'flex', alignItems: 'center', gap: 9, textDecoration: 'none', color: '#f5f5f7' }}>
            <LogoMark box={26} radius={7} icon={17} />
            <span style={{ fontSize: 15, fontWeight: 600, letterSpacing: '-0.01em' }}>Vitals</span>
          </Link>
          <Link
            to="/"
            style={{ fontSize: 13, color: 'rgba(235,235,245,0.62)', textDecoration: 'none', padding: '7px 12px', borderRadius: 9, border: '1px solid rgba(255,255,255,0.1)' }}
          >
            ← Back to Vitals
          </Link>
        </nav>
      </header>

      <main className="pt-[120px] md:pt-[150px]" style={{ maxWidth: 760, margin: '0 auto', paddingLeft: 24, paddingRight: 24, paddingBottom: 60 }}>
        <h1 className="text-[32px] md:text-[40px]" style={{ fontWeight: 670, letterSpacing: '-0.03em', lineHeight: 1.1, margin: `0 0 ${updated ? 10 : 24}px` }}>{title}</h1>
        {updated ? <p style={{ fontSize: 13, color: 'rgba(235,235,245,0.45)', margin: '0 0 42px' }}>Last updated: {updated}</p> : null}
        {children}
      </main>

      <footer style={{ maxWidth: 760, margin: '0 auto', padding: '0 24px 48px' }}>
        <div style={{ borderTop: '1px solid rgba(255,255,255,0.07)', paddingTop: 24, display: 'flex', flexWrap: 'wrap', gap: 12, justifyContent: 'space-between', fontSize: 12.5, color: 'rgba(235,235,245,0.4)' }}>
          <span>
            © {new Date().getFullYear()} {COMPANY} · Developed by{' '}
            <a href={DEVELOPER_URL} target="_blank" rel="noreferrer" style={{ color: 'rgba(235,235,245,0.55)', textDecoration: 'none' }}>
              {DEVELOPER} — rafay99.com
            </a>
          </span>
          <span style={{ display: 'flex', gap: 18 }}>
            <Link to="/terms" style={{ color: 'rgba(235,235,245,0.5)', textDecoration: 'none' }}>Terms</Link>
            <Link to="/privacy" style={{ color: 'rgba(235,235,245,0.5)', textDecoration: 'none' }}>Privacy</Link>
            <a href={REPO_URL} target="_blank" rel="noreferrer" style={{ color: 'rgba(235,235,245,0.5)', textDecoration: 'none' }}>GitHub</a>
          </span>
        </div>
      </footer>
    </div>
  )
}

export function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section style={{ marginBottom: 36 }}>
      <h2 style={{ fontSize: 21, fontWeight: 640, letterSpacing: '-0.02em', margin: '0 0 12px' }}>{title}</h2>
      {children}
    </section>
  )
}

export function P({ children }: { children: ReactNode }) {
  return <p style={{ fontSize: 15, lineHeight: 1.65, color: 'rgba(235,235,245,0.62)', margin: '0 0 12px' }}>{children}</p>
}

export function Item({ children }: { children: ReactNode }) {
  return <li style={{ fontSize: 15, lineHeight: 1.65, color: 'rgba(235,235,245,0.62)', marginBottom: 8 }}>{children}</li>
}

export function List({ children }: { children: ReactNode }) {
  return <ul style={{ margin: '0 0 12px', paddingLeft: 22 }}>{children}</ul>
}

export function Strong({ children }: { children: ReactNode }) {
  return <span style={{ color: '#f5f5f7', fontWeight: 590 }}>{children}</span>
}

export function ExtLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noreferrer" style={{ color: '#56AFFF', textDecoration: 'none' }}>
      {children}
    </a>
  )
}
