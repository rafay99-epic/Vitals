import type { ReactNode } from 'react'
import { ChipIcon, FanIcon, MemoryIcon, ThermoIcon } from './icons'

const mono = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"

// MARK: Menu-bar item — multiple live stats in Icons or Text style (#33/#34)

function MenuBarStrip({ style }: { style: 'Icons' | 'Text' }) {
  const items =
    style === 'Icons'
      ? [
          { icon: <ThermoIcon size={12} color="#FF9F4A" strokeWidth={2} />, value: '57°' },
          { icon: <ChipIcon size={12} color="#2AB0FF" strokeWidth={2} />, value: '23%' },
          { icon: <MemoryIcon size={12} color="#34D85F" strokeWidth={2} />, value: '12.8G' },
          { icon: <FanIcon size={12} color="#00D8F0" strokeWidth={1.8} />, value: '6516' },
        ]
      : [
          { label: 'Temp', value: '57°' },
          { label: 'CPU', value: '23%' },
          { label: 'RAM', value: '12.8G' },
          { label: 'Fan', value: '6516' },
        ]
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        height: 24,
        padding: '0 10px',
        gap: 12,
        borderRadius: 7,
        background: 'rgba(255,255,255,0.10)',
        border: '1px solid rgba(255,255,255,0.12)',
      }}
    >
      {items.map((it, i) => (
        <span key={i} style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, fontFamily: mono, color: '#f5f5f7' }}>
          {'icon' in it ? it.icon : <span style={{ color: 'rgba(235,235,245,0.55)' }}>{it.label}</span>}
          {it.value}
        </span>
      ))}
    </div>
  )
}

// MARK: dropdown panel — 2×2 metric cards with sparklines (#34)

const SPARKS: Record<string, string> = {
  up: '0,26 18,24 36,25 54,18 72,20 90,12 108,15 126,8 144,11 162,6',
  flat: '0,18 18,17 36,19 54,16 72,18 90,15 108,17 126,16 144,18 162,15',
}

function PanelCard({ tint, icon, title, value, spark }: { tint: string; icon: ReactNode; title: string; value: string; spark: string }) {
  return (
    <div style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: 11, padding: '11px 12px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 7 }}>
        {icon}
        <span style={{ fontSize: 11.5, color: 'rgba(235,235,245,0.6)' }}>{title}</span>
        <div style={{ flex: 1 }} />
        <span style={{ fontSize: 13, fontWeight: 640, fontFamily: mono }}>{value}</span>
      </div>
      <svg width="100%" height="30" viewBox="0 0 162 32" preserveAspectRatio="none" style={{ display: 'block', overflow: 'visible' }}>
        <polyline points={spark} fill="none" stroke={tint} strokeWidth="1.6" strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
      </svg>
    </div>
  )
}

function MenuBarPanel() {
  return (
    <div
      style={{
        width: 320,
        borderRadius: 16,
        overflow: 'hidden',
        background: 'linear-gradient(180deg, rgba(28,30,36,0.98), rgba(18,20,25,0.98))',
        border: '1px solid rgba(255,255,255,0.12)',
        boxShadow: '0 30px 70px -24px rgba(0,0,0,0.85)',
        padding: 14,
      }}
    >
      <div className="grid grid-cols-2" style={{ gap: 8, marginBottom: 12 }}>
        <PanelCard tint="#FF9F4A" icon={<ThermoIcon size={13} color="#FF9F4A" strokeWidth={1.8} />} title="Temp" value="57°" spark={SPARKS.up} />
        <PanelCard tint="#2AB0FF" icon={<ChipIcon size={13} color="#2AB0FF" strokeWidth={1.8} />} title="CPU" value="23%" spark={SPARKS.flat} />
        <PanelCard tint="#34D85F" icon={<MemoryIcon size={13} color="#34D85F" strokeWidth={1.8} />} title="Memory" value="12.8G" spark={SPARKS.flat} />
        <PanelCard tint="#BF5AF2" icon={<ChipIcon size={13} color="#BF5AF2" strokeWidth={1.8} />} title="GPU" value="60%" spark={SPARKS.up} />
      </div>
      <div style={{ display: 'flex', gap: 6 }}>
        {['Open Vitals', 'Copy diagnostics', 'Settings'].map((a, i) => (
          <span
            key={a}
            style={{
              flex: 1,
              textAlign: 'center',
              fontSize: 10.5,
              fontWeight: 500,
              padding: '6px 0',
              borderRadius: 8,
              color: i === 0 ? '#fff' : 'rgba(235,235,245,0.7)',
              background: i === 0 ? 'linear-gradient(180deg, #1a8cff, #0a72e8)' : 'rgba(255,255,255,0.06)',
              border: i === 0 ? 'none' : '1px solid rgba(255,255,255,0.1)',
            }}
          >
            {a}
          </span>
        ))}
      </div>
    </div>
  )
}

// MARK: desktop widgets — floating, "living" panels (#25)

function Widget({ tint, icon, label, value, sub, severity, children }: { tint: string; icon: ReactNode; label: string; value: string; sub: string; severity: number; children?: ReactNode }) {
  return (
    <div
      style={{
        width: 168,
        borderRadius: 18,
        padding: 16,
        background: 'linear-gradient(180deg, rgba(40,42,50,0.72), rgba(22,24,30,0.8))',
        backdropFilter: 'blur(30px) saturate(180%)',
        WebkitBackdropFilter: 'blur(30px) saturate(180%)',
        // The rim + inner heat-tint "breathe" with the real reading's severity.
        border: `1px solid ${tint}${severity > 0.5 ? '99' : '40'}`,
        boxShadow: `0 24px 50px -20px rgba(0,0,0,0.7), inset 0 0 ${28 * severity}px ${tint}${severity > 0.5 ? '30' : '14'}`,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 12 }}>
        <span style={{ width: 24, height: 24, borderRadius: 7, background: `${tint}24`, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>{icon}</span>
        <span style={{ fontSize: 12.5, color: 'rgba(235,235,245,0.65)' }}>{label}</span>
      </div>
      <div style={{ fontSize: 30, fontWeight: 700, letterSpacing: '-0.02em', fontFamily: mono }}>{value}</div>
      <div style={{ fontSize: 11.5, color: 'rgba(235,235,245,0.45)', marginTop: 3 }}>{sub}</div>
      {children}
    </div>
  )
}

export default function Glance() {
  return (
    <section id="glance" style={{ position: 'relative', padding: '80px 24px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      <div style={{ width: '100%', maxWidth: 1080 }}>
        <div style={{ textAlign: 'center', marginBottom: 44 }}>
          <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#00D8F0', marginBottom: 14 }}>WITHOUT OPENING THE APP</div>
          <h2 className="text-[32px] md:text-[44px]" style={{ fontWeight: 670, letterSpacing: '-0.035em', margin: '0 auto 16px', lineHeight: 1.06, maxWidth: '16ch' }}>
            Always a glance away.
          </h2>
          <p style={{ fontSize: 16, lineHeight: 1.5, color: 'rgba(235,235,245,0.55)', margin: '0 auto', maxWidth: '56ch' }}>
            Your vitals live in the menu bar and float on your desktop — every number a real reading, gently alive, costing almost nothing while it sits there.
          </p>
        </div>

        {/* Menu bar */}
        <div className="grid grid-cols-1 lg:grid-cols-[0.85fr_1.15fr] gap-8 lg:gap-12" style={{ alignItems: 'center', marginBottom: 56 }}>
          <div>
            <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#00D8F0', marginBottom: 12 }}>MENU BAR</div>
            <h3 className="text-[26px] md:text-[32px]" style={{ fontWeight: 660, letterSpacing: '-0.03em', margin: '0 0 14px', lineHeight: 1.12 }}>
              Your stats, up top.
            </h3>
            <p style={{ fontSize: 15.5, lineHeight: 1.55, color: 'rgba(235,235,245,0.6)', margin: '0 0 12px' }}>
              Pick any mix of CPU temperature, CPU and GPU load, memory, and fan speed — in compact <span style={{ color: '#f5f5f7' }}>Icons</span> or labelled
              <span style={{ color: '#f5f5f7' }}> Text</span>. The fan spins with real rpm, the rest gently breathe.
            </p>
            <p style={{ fontSize: 15.5, lineHeight: 1.55, color: 'rgba(235,235,245,0.6)', margin: 0 }}>
              Drawn live on the GPU at your display's own refresh rate — 120 Hz on ProMotion — for near-zero CPU. Click for a 2×2 panel of sparklines and quick actions.
            </p>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18 }}>
            {/* faux menu bar */}
            <div
              style={{
                width: '100%',
                maxWidth: 420,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'flex-end',
                gap: 14,
                height: 30,
                padding: '0 12px',
                borderRadius: 9,
                background: 'rgba(255,255,255,0.04)',
                border: '1px solid rgba(255,255,255,0.08)',
              }}
            >
              <MenuBarStrip style="Icons" />
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="rgba(235,235,245,0.55)" strokeWidth="1.6"><circle cx="11" cy="11" r="7" /><path d="M16 16l5 5" /></svg>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="rgba(235,235,245,0.6)"><path d="M12 2a4 4 0 0 0-4 4v1a6 6 0 0 0-3 5v3l-2 2v1h18v-1l-2-2v-3a6 6 0 0 0-3-5V6a4 4 0 0 0-4-4z" /></svg>
              <span style={{ fontSize: 11.5, fontFamily: mono, color: 'rgba(235,235,245,0.7)' }}>9:41</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 11.5, color: 'rgba(235,235,245,0.4)' }}>
              <MenuBarStrip style="Text" />
              <span>Text style</span>
            </div>
            <MenuBarPanel />
          </div>
        </div>

        {/* Desktop widgets */}
        <div className="grid grid-cols-1 lg:grid-cols-[1.15fr_0.85fr] gap-8 lg:gap-12" style={{ alignItems: 'center' }}>
          <div
            className="order-last lg:order-first"
            style={{
              position: 'relative',
              borderRadius: 20,
              padding: '36px 24px',
              background: 'radial-gradient(120% 120% at 20% 0%, rgba(10,132,255,0.12), transparent 55%), radial-gradient(120% 120% at 90% 100%, rgba(191,90,242,0.12), transparent 55%), rgba(255,255,255,0.02)',
              border: '1px solid rgba(255,255,255,0.07)',
              display: 'flex',
              flexWrap: 'wrap',
              gap: 16,
              justifyContent: 'center',
            }}
          >
            <Widget tint="#FF5847" icon={<ThermoIcon size={13} color="#FF5847" strokeWidth={1.8} />} label="CPU temp" value="71°" sub="hottest core 78°" severity={0.85} />
            <Widget tint="#34D85F" icon={<MemoryIcon size={13} color="#34D85F" strokeWidth={1.8} />} label="Memory" value="9.4 GB" sub="of 16 GB" severity={0.35} />
            <Widget tint="#00D8F0" icon={<FanIcon size={13} color="#00D8F0" strokeWidth={1.7} />} label="Fan" value="0 rpm" sub="idle · not spinning" severity={0} />
          </div>
          <div>
            <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#BF5AF2', marginBottom: 12 }}>DESKTOP WIDGETS</div>
            <h3 className="text-[26px] md:text-[32px]" style={{ fontWeight: 660, letterSpacing: '-0.03em', margin: '0 0 14px', lineHeight: 1.12 }}>
              Living panels on your desktop.
            </h3>
            <p style={{ fontSize: 15.5, lineHeight: 1.55, color: 'rgba(235,235,245,0.6)', margin: '0 0 12px' }}>
              Frosted glass panels you place anywhere, drag to move, and drag the corner to resize — the numbers and charts scale with them.
            </p>
            <p style={{ fontSize: 15.5, lineHeight: 1.55, color: 'rgba(235,235,245,0.6)', margin: 0 }}>
              Each one quietly <span style={{ color: '#f5f5f7' }}>warms its rim</span> as the reading it watches climbs — and a fan at <span style={{ color: '#f5f5f7' }}>0 rpm</span> sits
              perfectly still, because it really isn't spinning.
            </p>
          </div>
        </div>
      </div>
    </section>
  )
}
