import { Link } from '@tanstack/react-router'
import { HeartbeatIcon } from './icons'
import { COMPANY, DEVELOPER, DEVELOPER_URL, REPO_URL } from '../lib/links'

const footLink: React.CSSProperties = { color: 'rgba(235,235,245,0.5)', textDecoration: 'none' }

export default function Footer() {
  return (
    <footer style={{ position: 'relative', padding: '28px 24px 48px', display: 'flex', justifyContent: 'center' }}>
      <div style={{ width: '100%', maxWidth: 1080, paddingTop: 28, borderTop: '1px solid rgba(255,255,255,0.07)' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
            <div
              style={{
                width: 22,
                height: 22,
                borderRadius: 6,
                background: 'linear-gradient(160deg, #2a2a2e, #161618)',
                border: '1px solid rgba(255,255,255,0.12)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              <HeartbeatIcon size={14} />
            </div>
            <span style={{ fontSize: 13.5, fontWeight: 600 }}>Vitals</span>
            <span style={{ fontSize: 12.5, color: 'rgba(235,235,245,0.4)', marginLeft: 4 }}>Take care of your Mac.</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 22, fontSize: 12.5 }}>
            <a href="/#philosophy" style={footLink}>Philosophy</a>
            <a href="/#sensors" style={footLink}>Sensors</a>
            <Link to="/releases" style={footLink}>Releases</Link>
            <a href={REPO_URL} target="_blank" rel="noreferrer" style={footLink}>GitHub</a>
          </div>
        </div>
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            flexWrap: 'wrap',
            gap: 12,
            marginTop: 18,
            fontSize: 12,
            color: 'rgba(235,235,245,0.35)',
          }}
        >
          <span>
            © {new Date().getFullYear()} {COMPANY} · Developed by{' '}
            <a href={DEVELOPER_URL} target="_blank" rel="noreferrer" style={{ color: 'rgba(235,235,245,0.5)', textDecoration: 'none' }}>
              {DEVELOPER} — rafay99.com
            </a>{' '}
            · Free software under{' '}
            <a href={`${REPO_URL}/blob/main/LICENSE`} target="_blank" rel="noreferrer" style={{ color: 'rgba(235,235,245,0.5)', textDecoration: 'none' }}>
              GPL-3.0
            </a>{' '}
            · Cleanup informed by{' '}
            <a href="https://github.com/tw93/mole" target="_blank" rel="noreferrer" style={{ color: 'rgba(235,235,245,0.5)', textDecoration: 'none' }}>
              Mole
            </a>
          </span>
          <span style={{ display: 'flex', gap: 18 }}>
            <Link to="/terms" style={footLink}>Terms &amp; Conditions</Link>
            <Link to="/privacy" style={footLink}>Privacy Policy</Link>
          </span>
        </div>
      </div>
    </footer>
  )
}
