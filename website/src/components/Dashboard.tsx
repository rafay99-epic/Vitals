import type { ReactNode } from 'react'
import type { LiveVitals } from '../lib/useLiveVitals'
import { ChipIcon, FanIcon, MemoryIcon, ThermoIcon } from './icons'

const mono = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"

function StatCard({ icon, label, value, sub }: { icon: ReactNode; label: string; value: string; sub: string }) {
  return (
    <div style={{ background: '#161C26', border: '1px solid rgba(255,255,255,0.06)', borderRadius: 13, padding: '15px 16px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
        {icon}
        <span style={{ fontSize: 13.5, color: 'rgba(235,235,245,0.62)' }}>{label}</span>
      </div>
      <div style={{ fontSize: 30, fontWeight: 700, letterSpacing: '-0.02em' }}>{value}</div>
      <div style={{ fontSize: 12.5, color: 'rgba(235,235,245,0.4)', marginTop: 5 }}>{sub}</div>
    </div>
  )
}

// Die cells with the design's three heat tints.
const DIE_CELLS: { label: string; temp: number; tint: 0 | 1 | 2 }[] = [
  { label: 'A1', temp: 38, tint: 0 }, { label: 'A2', temp: 38, tint: 0 }, { label: 'A3', temp: 38, tint: 0 },
  { label: 'A4', temp: 38, tint: 0 }, { label: 'A5', temp: 39, tint: 1 }, { label: 'A6', temp: 40, tint: 2 },
  { label: 'A7', temp: 40, tint: 2 }, { label: 'A8', temp: 39, tint: 1 }, { label: 'A9', temp: 38, tint: 0 },
  { label: 'A10', temp: 37, tint: 0 }, { label: 'A11', temp: 38, tint: 0 }, { label: 'A12', temp: 38, tint: 0 },
]
const TINTS = [
  { background: 'rgba(40,131,38,0.18)', border: '1px solid rgba(50,180,60,0.5)' },
  { background: 'rgba(60,140,38,0.2)', border: '1px solid rgba(90,190,55,0.5)' },
  { background: 'rgba(90,150,38,0.22)', border: '1px solid rgba(130,200,55,0.5)' },
]

function legendDot(color: string) {
  return <span style={{ width: 8, height: 8, borderRadius: '50%', background: color }} />
}

export default function Dashboard({ vitals }: { vitals: LiveVitals }) {
  return (
    <section style={{ position: 'relative', padding: '30px 24px 80px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      <div style={{ textAlign: 'center', maxWidth: 1080, marginBottom: 36 }}>
        <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#34D85F', marginBottom: 14 }}>LOOKS LIKE APPLE MADE IT</div>
        <h2 style={{ fontSize: 44, fontWeight: 670, letterSpacing: '-0.035em', margin: '0 auto 16px', lineHeight: 1.06, maxWidth: '16ch' }}>
          The whole picture, in one window.
        </h2>
        <p style={{ fontSize: 16, lineHeight: 1.5, color: 'rgba(235,235,245,0.55)', margin: '0 auto', maxWidth: '56ch' }}>
          Open the full app for the complete dashboard — live thermals, per-die sensors, fan control, memory and battery. Native window chrome, real
          macOS materials.
        </p>
      </div>

      {/* macOS window */}
      <div
        style={{
          position: 'relative',
          width: '100%',
          maxWidth: 1040,
          borderRadius: 14,
          overflow: 'hidden',
          background: 'linear-gradient(180deg, rgba(16,19,24,0.96), rgba(11,13,17,0.97))',
          border: '1px solid rgba(255,255,255,0.1)',
          boxShadow: '0 50px 110px -30px rgba(0,0,0,0.85), 0 2px 10px rgba(0,0,0,0.5)',
        }}
      >
        {/* title bar */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            padding: '0 16px',
            height: 44,
            background: 'linear-gradient(180deg, rgba(40,42,48,0.9), rgba(28,30,35,0.9))',
            borderBottom: '1px solid rgba(255,255,255,0.06)',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ width: 12, height: 12, borderRadius: '50%', background: '#FF5F57' }} />
            <span style={{ width: 12, height: 12, borderRadius: '50%', background: '#FEBC2E' }} />
            <span style={{ width: 12, height: 12, borderRadius: '50%', background: '#28C840' }} />
          </div>
          <span style={{ flex: 1, textAlign: 'center', fontSize: 14, fontWeight: 600, color: '#f5f5f7', marginLeft: -52 }}>Vitals</span>
          <div style={{ width: 30, height: 30, borderRadius: '50%', border: '1px solid rgba(255,255,255,0.14)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="rgba(235,235,245,0.7)" strokeWidth="1.6">
              <circle cx="12" cy="12" r="3.2" />
              <path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M19.1 4.9L17 7M7 17l-2.1 2.1" />
            </svg>
          </div>
        </div>

        {/* window body */}
        <div style={{ padding: 20 }}>
          {/* stat cards */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginBottom: 14 }}>
            <StatCard icon={<ChipIcon size={17} color="#34D85F" />} label="Average CPU" value="37.3°" sub="24 die sensors" />
            <StatCard
              icon={
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#FF9F4A" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M12 2c1 3-1 4-2 6s0 4 2 4 3-2 2-4c3 1 4 4 4 6a6 6 0 1 1-12 0c0-3 2-5 4-8 1-1.5 1-2.5 0-4z" />
                </svg>
              }
              label="Hottest Core"
              value="40.0°"
              sub="Sensor A6"
            />
            <StatCard icon={<FanIcon size={17} color="#00D8F0" strokeWidth={1.6} />} label="Fan" value="0 rpm" sub="Max 6550 rpm" />
            <StatCard
              icon={
                <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="#2AB0FF" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
                  <circle cx="12" cy="13" r="8" />
                  <path d="M12 13l4-3M12 5V3M5 6l1 1M19 6l-1 1" />
                </svg>
              }
              label="CPU Usage"
              value="28%"
              sub="10 cores"
            />
            <StatCard icon={<MemoryIcon size={17} color="#34D85F" />} label="Memory" value="12.7 GB" sub="of 16 GB · Normal pressure" />
            <StatCard icon={<ThermoIcon size={17} color="#34D85F" />} label="Thermal Pressure" value="Nominal" sub="Reported by macOS" />
          </div>

          {/* temperature chart */}
          <div style={{ background: '#131922', border: '1px solid rgba(255,255,255,0.06)', borderRadius: 14, padding: '18px 20px', marginBottom: 14 }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 18 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
                <ThermoIcon size={16} color="rgba(235,235,245,0.7)" />
                <span style={{ fontSize: 15, fontWeight: 600 }}>Temperature · last 5 minutes</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 16, fontSize: 12.5 }}>
                <span style={{ display: 'flex', alignItems: 'center', gap: 6, color: 'rgba(235,235,245,0.6)' }}>{legendDot('#FFA318')}CPU average</span>
                <span style={{ display: 'flex', alignItems: 'center', gap: 6, color: 'rgba(235,235,245,0.6)' }}>{legendDot('#E0494B')}Hottest core</span>
                <span style={{ display: 'flex', alignItems: 'center', gap: 6, color: 'rgba(235,235,245,0.6)' }}>{legendDot('#F83EFF')}GPU</span>
              </div>
            </div>
            <div style={{ display: 'flex', gap: 10 }}>
              <div style={{ position: 'relative', flex: 1, height: 200 }}>
                <svg width="100%" height="100%" viewBox="0 0 1000 200" preserveAspectRatio="none" style={{ display: 'block', overflow: 'visible' }}>
                  <line x1="0" y1="15" x2="1000" y2="15" stroke="rgba(255,255,255,0.06)" />
                  <line x1="0" y1="77" x2="1000" y2="77" stroke="rgba(255,255,255,0.06)" />
                  <line x1="0" y1="138" x2="1000" y2="138" stroke="rgba(255,255,255,0.06)" />
                  <line x1="0" y1="199" x2="1000" y2="199" stroke="rgba(255,255,255,0.1)" />
                  <polyline points={vitals.chartGpu} fill="none" stroke="#F83EFF" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" opacity="0.85" />
                  <polyline points={vitals.chartHot} fill="none" stroke="#E0494B" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
                  <polyline points={vitals.chartCpu} fill="none" stroke="#FFA318" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
                </svg>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'space-between', fontSize: 11.5, color: 'rgba(235,235,245,0.4)', fontFamily: mono, padding: '6px 0' }}>
                <span>°C</span><span>60</span><span>40</span><span>20</span><span>0</span>
              </div>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11.5, color: 'rgba(235,235,245,0.4)', marginTop: 8, paddingRight: 28 }}>
              <span>6:38 PM</span><span>6:39 PM</span><span>6:40 PM</span><span>6:41 PM</span>
            </div>
          </div>

          {/* die grid + fans */}
          <div style={{ display: 'grid', gridTemplateColumns: '1.6fr 1fr', gap: 14 }}>
            {/* die grid */}
            <div style={{ background: '#131922', border: '1px solid rgba(255,255,255,0.06)', borderRadius: 14, padding: '18px 20px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 9, marginBottom: 16 }}>
                <ChipIcon size={16} color="rgba(235,235,245,0.7)" />
                <span style={{ fontSize: 15, fontWeight: 600 }}>CPU die temperatures</span>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(6, 1fr)', gap: 8 }}>
                {DIE_CELLS.map((cell) => (
                  <div key={cell.label} style={{ ...TINTS[cell.tint], borderRadius: 9, padding: '9px 0', textAlign: 'center' }}>
                    <div style={{ fontSize: 11, color: 'rgba(235,235,245,0.55)' }}>{cell.label}</div>
                    <div style={{ fontSize: 16, fontWeight: 600, marginTop: 2 }}>{cell.temp}°</div>
                  </div>
                ))}
              </div>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 16, fontSize: 12.5, color: 'rgba(235,235,245,0.5)' }}>
                <div style={{ display: 'flex', gap: 16 }}>
                  <span>Coolest 37°</span><span>Average 38°</span><span>Hottest 40°</span>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span style={{ width: 90, height: 7, borderRadius: 4, background: 'linear-gradient(90deg, #34D85F, #C8E04A, #FF9F4A, #E0494B)' }} />
                  <span>40°–90°</span>
                </div>
              </div>
            </div>

            {/* fans */}
            <div style={{ background: '#131922', border: '1px solid rgba(255,255,255,0.06)', borderRadius: 14, padding: '18px 20px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 9, marginBottom: 18 }}>
                <FanIcon size={16} color="#00D8F0" strokeWidth={1.6} />
                <span style={{ fontSize: 15, fontWeight: 600 }}>Fans</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 18 }}>
                <div style={{ position: 'relative', width: 72, height: 72, flexShrink: 0 }}>
                  <svg width="72" height="72" viewBox="0 0 72 72">
                    <circle cx="36" cy="36" r="30" fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth="5" />
                    <circle cx="36" cy="36" r="30" fill="none" stroke="#0E9DB5" strokeWidth="5" strokeLinecap="round" strokeDasharray="188" strokeDashoffset="188" transform="rotate(-90 36 36)" />
                  </svg>
                  <div style={{ position: 'absolute', top: 25, left: 25 }}>
                    <FanIcon size={22} color="rgba(235,235,245,0.8)" strokeWidth={1.5} />
                  </div>
                </div>
                <div>
                  <div style={{ fontSize: 22, fontWeight: 700 }}>0 rpm</div>
                  <div style={{ fontSize: 13.5, color: 'rgba(235,235,245,0.7)', marginTop: 2 }}>Automatic</div>
                  <div style={{ fontSize: 12.5, color: 'rgba(235,235,245,0.42)', marginTop: 2 }}>Range 2,317–6,550 rpm</div>
                </div>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 16 }}>
                <div style={{ flex: 1, height: 6, borderRadius: 4, background: 'rgba(255,255,255,0.1)', position: 'relative' }}>
                  <div style={{ position: 'absolute', left: 0, top: '50%', transform: 'translateY(-50%)', width: 16, height: 16, borderRadius: '50%', background: '#fff', boxShadow: '0 1px 4px rgba(0,0,0,0.5)' }} />
                </div>
                <span style={{ fontSize: 12.5, color: 'rgba(235,235,245,0.6)', fontFamily: mono }}>2,317</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <span style={{ fontSize: 12.5, color: 'rgba(235,235,245,0.45)', lineHeight: 1.4, maxWidth: '60%' }}>
                  Manual speed overrides macOS cooling, within the rated range.
                </span>
                <span style={{ fontSize: 12.5, fontWeight: 500, padding: '6px 12px', borderRadius: 8, background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.1)' }}>
                  Disable…
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
