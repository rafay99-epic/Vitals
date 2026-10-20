import { CheckIcon } from './icons'

const mono = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"

const GUARANTEES = [
  "Clamped to safe RPM ranges — you can't drive it past the limit.",
  'Password-gated, every single time you apply a change.',
  'macOS thermal safety stays in control — Vitals never overrides it.',
]

export default function FanControl() {
  return (
    <section style={{ position: 'relative', padding: '60px 24px 80px', display: 'flex', justifyContent: 'center' }}>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-10 lg:gap-12" style={{ width: '100%', maxWidth: 1080, alignItems: 'center' }}>
        <div
          style={{
            position: 'relative',
            background: 'linear-gradient(180deg, rgba(44,44,48,0.7), rgba(24,24,27,0.78))',
            backdropFilter: 'blur(40px) saturate(180%)',
            WebkitBackdropFilter: 'blur(40px) saturate(180%)',
            border: '1px solid rgba(255,255,255,0.12)',
            borderRadius: 20,
            padding: 22,
            boxShadow: '0 30px 70px -24px rgba(0,0,0,0.8), inset 0 1px 0 rgba(255,255,255,0.12)',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 20 }}>
            <span style={{ fontSize: 14, fontWeight: 600 }}>Fan Control</span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 11, color: 'rgba(50,215,75,0.95)', padding: '3px 9px', background: 'rgba(50,215,75,0.12)', borderRadius: 7 }}>
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#32D74B" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 2l8 4v5c0 5-3.5 8.5-8 11-4.5-2.5-8-6-8-11V6z" />
              </svg>
              Safety net active
            </span>
          </div>
          <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.06em', color: 'rgba(235,235,245,0.4)', marginBottom: 8 }}>TARGET SPEED</div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 4, marginBottom: 16 }}>
            <span style={{ fontFamily: mono, fontSize: 32, fontWeight: 600 }}>2,400</span>
            <span style={{ fontSize: 14, color: 'rgba(235,235,245,0.5)' }}>rpm</span>
          </div>
          <div style={{ position: 'relative', height: 8, borderRadius: 4, background: 'rgba(255,255,255,0.1)', marginBottom: 8 }}>
            <div style={{ position: 'absolute', left: 0, top: 0, height: '100%', width: '52%', borderRadius: 4, background: 'linear-gradient(90deg, #0A84FF, #1a8cff)' }} />
            <div style={{ position: 'absolute', left: '52%', top: '50%', transform: 'translate(-50%,-50%)', width: 18, height: 18, borderRadius: '50%', background: '#fff', boxShadow: '0 2px 6px rgba(0,0,0,0.5)' }} />
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: mono, fontSize: 10.5, color: 'rgba(235,235,245,0.35)', marginBottom: 18 }}>
            <span>1,200 min</span>
            <span>4,600 max</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '11px 13px', background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 11 }}>
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="rgba(235,235,245,0.6)" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <rect x="5" y="11" width="14" height="10" rx="2" />
              <path d="M8 11V7a4 4 0 0 1 8 0v4" />
            </svg>
            <span style={{ fontSize: 12.5, color: 'rgba(235,235,245,0.6)' }}>Touch ID required to apply</span>
          </div>
        </div>
        <div style={{ position: 'relative', zIndex: 2 }}>
          <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#0A84FF', marginBottom: 14 }}>READ FREELY, WRITE CAREFULLY</div>
          <h2 className="text-[30px] md:text-[38px]" style={{ fontWeight: 660, letterSpacing: '-0.03em', margin: '0 0 18px', lineHeight: 1.1 }}>
            The one thing that changes hardware gets the most caution.
          </h2>
          <p style={{ fontSize: 16, lineHeight: 1.55, color: 'rgba(235,235,245,0.6)', margin: '0 0 24px' }}>
            Fan control is the only place Vitals writes to your Mac, so it's wrapped in deliberate friction: values clamp to the manufacturer's safe
            range, every change needs your password, and macOS's own thermal protection stays underneath at all times.
          </p>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {GUARANTEES.map((text) => (
              <div key={text} style={{ display: 'flex', alignItems: 'flex-start', gap: 11 }}>
                <CheckIcon />
                <span style={{ fontSize: 14.5, color: 'rgba(235,235,245,0.72)', lineHeight: 1.4 }}>{text}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}
