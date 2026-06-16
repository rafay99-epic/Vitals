import { LogoMark } from './icons'
import { REPO_URL } from '../lib/links'

const link: React.CSSProperties = {
  fontSize: 13,
  color: 'rgba(235,235,245,0.62)',
  textDecoration: 'none',
  padding: '6px 11px',
  borderRadius: 8,
}

export default function Nav() {
  return (
    <header style={{ position: 'fixed', top: 0, left: 0, right: 0, zIndex: 100, display: 'flex', justifyContent: 'center', padding: '14px 20px' }}>
      <nav
        style={{
          width: '100%',
          maxWidth: 1080,
          display: 'flex',
          alignItems: 'center',
          gap: 20,
          padding: '9px 12px 9px 16px',
          background: 'rgba(20,20,23,0.6)',
          backdropFilter: 'blur(28px) saturate(180%)',
          WebkitBackdropFilter: 'blur(28px) saturate(180%)',
          border: '1px solid rgba(255,255,255,0.09)',
          borderRadius: 17,
          boxShadow: '0 10px 40px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.06)',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
          <LogoMark box={26} radius={7} icon={17} />
          <span style={{ fontSize: 15, fontWeight: 600, letterSpacing: '-0.01em' }}>Vitals</span>
        </div>
        <div className="hidden md:flex" style={{ flex: 1, alignItems: 'center', gap: 4, justifyContent: 'center' }}>
          <a href="#sensors" style={link}>Sensors</a>
          <a href="#monitor" style={link}>Monitor</a>
          <a href="#glance" style={link}>Glance</a>
          <a href="#manage" style={link}>Manage</a>
          <a href="#download" style={link}>Download</a>
        </div>
        <div className="flex-1 md:hidden" />
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <a
            href={REPO_URL}
            target="_blank"
            rel="noreferrer"
            style={{ fontSize: 13, color: 'rgba(235,235,245,0.62)', textDecoration: 'none', padding: '7px 12px', borderRadius: 9, border: '1px solid rgba(255,255,255,0.1)' }}
          >
            GitHub
          </a>
          <a
            href="#download"
            style={{
              fontSize: 13,
              fontWeight: 590,
              color: '#fff',
              textDecoration: 'none',
              padding: '7px 15px',
              borderRadius: 9,
              background: 'linear-gradient(180deg, #1a8cff, #0a72e8)',
              boxShadow: '0 2px 10px rgba(10,132,255,0.4), inset 0 1px 0 rgba(255,255,255,0.25)',
            }}
          >
            Download
          </a>
        </div>
      </nav>
    </header>
  )
}
