const mono = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"

const PRINCIPLES = [
  {
    number: '01',
    numberColor: 'rgba(235,235,245,0.3)',
    background: 'linear-gradient(180deg, rgba(255,255,255,0.05), rgba(255,255,255,0.02))',
    border: '1px solid rgba(255,255,255,0.08)',
    title: "Don't stick out — belong to the system.",
    body: "No custom-drawn buttons. System fonts only, SF Symbols, real window chrome, the native Settings window, Liquid Glass. Glance at it and you can't tell it didn't ship with macOS.",
  },
  {
    number: '02',
    numberColor: 'rgba(255,159,10,0.7)',
    background: 'linear-gradient(180deg, rgba(255,159,10,0.06), rgba(255,255,255,0.02))',
    border: '1px solid rgba(255,159,10,0.16)',
    title: 'Honesty over decoration.',
    body: 'Every number is a real reading from your actual hardware. No smoothing that lies, no fake gauges. When the fan reads zero, we say "fanless / idle" instead of hiding it.',
  },
  {
    number: '03',
    numberColor: 'rgba(50,215,75,0.7)',
    background: 'linear-gradient(180deg, rgba(50,215,75,0.06), rgba(255,255,255,0.02))',
    border: '1px solid rgba(50,215,75,0.16)',
    title: 'Read freely, write carefully.',
    body: "Reading sensors is harmless, so we do it liberally. The moment we touch fan control, the philosophy flips to maximum caution: clamp to safe ranges, require a password, keep macOS's safety net underneath.",
  },
  {
    number: '04',
    numberColor: 'rgba(235,235,245,0.3)',
    background: 'linear-gradient(180deg, rgba(255,255,255,0.05), rgba(255,255,255,0.02))',
    border: '1px solid rgba(255,255,255,0.08)',
    title: "Layers that don't leak.",
    body: 'Services talk to hardware and know nothing about the UI. The model polls and publishes. Views only display. Good structure is what makes "I have so many plans for this" actually possible.',
  },
]

export default function Philosophy() {
  return (
    <section id="philosophy" style={{ position: 'relative', padding: '80px 24px 90px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      <div style={{ width: '100%', maxWidth: 1080 }}>
        <div style={{ textAlign: 'center', marginBottom: 48 }}>
          <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#0A84FF', marginBottom: 14 }}>THE PHILOSOPHY</div>
          <h2 className="text-[32px] md:text-[44px]" style={{ fontWeight: 670, letterSpacing: '-0.035em', margin: '0 auto 16px', lineHeight: 1.06, maxWidth: '18ch' }}>
            A monitoring tool that fudges its numbers is worse than useless.
          </h2>
          <p style={{ fontSize: 16, lineHeight: 1.5, color: 'rgba(235,235,245,0.55)', margin: '0 auto', maxWidth: '56ch' }}>
            Four principles hold the whole thing together. They're why we can keep adding features without it collapsing.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2" style={{ gap: 14 }}>
          {PRINCIPLES.map((p) => (
            <div key={p.number} style={{ position: 'relative', background: p.background, border: p.border, borderRadius: 18, padding: '28px 28px 30px', overflow: 'hidden' }}>
              <div style={{ fontFamily: mono, fontSize: 13, fontWeight: 600, color: p.numberColor, marginBottom: 16 }}>{p.number}</div>
              <h3 style={{ fontSize: 21, fontWeight: 640, letterSpacing: '-0.02em', margin: '0 0 10px' }}>{p.title}</h3>
              <p style={{ fontSize: 14.5, lineHeight: 1.55, color: 'rgba(235,235,245,0.58)', margin: 0 }}>{p.body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
