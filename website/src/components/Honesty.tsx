const mono = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"

export default function Honesty() {
  return (
    <section id="honesty" style={{ position: 'relative', padding: '70px 24px', display: 'flex', justifyContent: 'center' }}>
      <div
        style={{
          width: '100%',
          maxWidth: 1080,
          background: 'linear-gradient(180deg, rgba(20,20,23,0.6), rgba(14,14,16,0.6))',
          border: '1px solid rgba(255,255,255,0.08)',
          borderRadius: 26,
          padding: 52,
          display: 'grid',
          gridTemplateColumns: '1.05fr 1fr',
          gap: 48,
          alignItems: 'center',
        }}
      >
        <div>
          <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#FF9F0A', marginBottom: 14 }}>WHEN THE FAN READS ZERO</div>
          <h2 style={{ fontSize: 38, fontWeight: 660, letterSpacing: '-0.03em', margin: '0 0 18px', lineHeight: 1.1 }}>Most apps would invent a number.</h2>
          <p style={{ fontSize: 16, lineHeight: 1.55, color: 'rgba(235,235,245,0.6)', margin: '0 0 14px' }}>
            On a fanless Mac, or one sitting cool and idle, the fan genuinely isn't spinning. A dashboard that shows a comforting "1,980 rpm" anyway is
            lying to you.
          </p>
          <p style={{ fontSize: 16, lineHeight: 1.55, color: 'rgba(235,235,245,0.6)', margin: 0 }}>
            Vitals tells the truth: <span style={{ color: '#f5f5f7', fontWeight: 560 }}>fanless / idle</span>. The same instinct runs everywhere — on
            M4, GPU temperature isn't separately exposed, so we don't draw a line for it rather than fake one.
          </p>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <div style={{ background: 'rgba(255,69,58,0.06)', border: '1px solid rgba(255,69,58,0.18)', borderRadius: 14, padding: '16px 18px' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
              <span style={{ fontSize: 12, fontWeight: 600, color: 'rgba(255,99,90,0.9)' }}>OTHER TOOLS</span>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#FF453A" strokeWidth="2" strokeLinecap="round">
                <circle cx="12" cy="12" r="9" />
                <path d="M9 9l6 6M15 9l-6 6" />
              </svg>
            </div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
              <span style={{ fontFamily: mono, fontSize: 26, fontWeight: 500, color: 'rgba(235,235,245,0.55)', textDecoration: 'line-through', textDecorationColor: 'rgba(255,69,58,0.7)' }}>
                1,980 rpm
              </span>
              <span style={{ fontSize: 12, color: 'rgba(255,99,90,0.85)' }}>fabricated</span>
            </div>
          </div>
          <div style={{ background: 'rgba(50,215,75,0.07)', border: '1px solid rgba(50,215,75,0.22)', borderRadius: 14, padding: '16px 18px' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
              <span style={{ fontSize: 12, fontWeight: 600, color: 'rgba(50,215,75,0.95)' }}>VITALS</span>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#32D74B" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="9" />
                <path d="M8 12l3 3 5-6" />
              </svg>
            </div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
              <span style={{ fontFamily: mono, fontSize: 26, fontWeight: 500, color: '#f5f5f7' }}>Fanless / idle</span>
              <span style={{ fontSize: 12, color: 'rgba(50,215,75,0.9)' }}>honest</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
