import { HeartbeatIcon } from './icons'
import { REPO_URL } from '../lib/links'

const footLink: React.CSSProperties = { color: 'rgba(235,235,245,0.5)', textDecoration: 'none' }

export default function Footer() {
  return (
    <footer style={{ position: 'relative', padding: '28px 24px 48px', display: 'flex', justifyContent: 'center' }}>
      <div
        style={{
          width: '100%',
          maxWidth: 1080,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          flexWrap: 'wrap',
          gap: 16,
          paddingTop: 28,
          borderTop: '1px solid rgba(255,255,255,0.07)',
        }}
      >
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
          <a href="#philosophy" style={footLink}>Philosophy</a>
          <a href="#sensors" style={footLink}>Sensors</a>
          <a href="#download" style={footLink}>Download</a>
          <a href={REPO_URL} target="_blank" rel="noreferrer" style={footLink}>GitHub</a>
        </div>
      </div>
    </footer>
  )
}
