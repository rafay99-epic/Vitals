import type { ReactNode } from 'react'
import type { LiveVitals } from '../lib/useLiveVitals'
import { ChipIcon, FanIcon, ThermoIcon } from './icons'

const mono = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"

function SensorCard({ iconBg, icon, value, title, body }: { iconBg: string; icon: ReactNode; value: string; title: string; body: string }) {
  return (
    <div style={{ background: 'rgba(255,255,255,0.035)', border: '1px solid rgba(255,255,255,0.07)', borderRadius: 16, padding: 20 }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 28 }}>
        <div style={{ width: 36, height: 36, borderRadius: 9, background: iconBg, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          {icon}
        </div>
        <span style={{ fontFamily: mono, fontSize: 18, fontWeight: 500, color: '#f5f5f7' }}>{value}</span>
      </div>
      <div style={{ fontSize: 15, fontWeight: 590, marginBottom: 4 }}>{title}</div>
      <div style={{ fontSize: 13, color: 'rgba(235,235,245,0.5)', lineHeight: 1.45 }}>{body}</div>
    </div>
  )
}

export default function Sensors({ vitals }: { vitals: LiveVitals }) {
  return (
    <section id="sensors" style={{ position: 'relative', padding: '80px 24px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      <div style={{ width: '100%', maxWidth: 1080 }}>
        <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', flexWrap: 'wrap', gap: 16, marginBottom: 36 }}>
          <div>
            <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#FF9F0A', marginBottom: 12 }}>EVERY READING IS REAL</div>
            <h2 className="text-[30px] md:text-[40px]" style={{ fontWeight: 660, letterSpacing: '-0.03em', margin: 0, lineHeight: 1.08 }}>Straight from the silicon.</h2>
          </div>
          <p style={{ fontSize: 15, lineHeight: 1.5, color: 'rgba(235,235,245,0.55)', margin: 0, maxWidth: '38ch' }}>
            No estimates, no smoothing that lies. Vitals taps the same private sensors macOS uses internally — the IOKit HID thermal interface and the
            SMC.
          </p>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3" style={{ gap: 12 }}>
          <SensorCard
            iconBg="rgba(255,159,74,0.14)"
            icon={<ThermoIcon size={20} color="#FF9F4A" strokeWidth={1.8} />}
            value={`${vitals.cpuTemp}°C`}
            title="Chip temperature"
            body="Per-cluster die readings from the thermal HID sensors — not a guess from power draw."
          />
          <SensorCard
            iconBg="rgba(0,216,240,0.13)"
            icon={<FanIcon size={20} color="#00D8F0" strokeWidth={1.8} />}
            value={vitals.fanLabel}
            title="Fan speed"
            body="Live RPM from the SMC. When the fan isn't spinning, it says so — no phantom numbers."
          />
          <SensorCard
            iconBg="rgba(50,215,75,0.14)"
            icon={
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#32D74B" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <rect x="2" y="7" width="17" height="10" rx="2.5" />
                <path d="M22 10.5v3" />
                <rect x="4.5" y="9.5" width="9" height="5" rx="1" fill="#32D74B" stroke="none" />
              </svg>
            }
            value="98%"
            title="Battery health"
            body="Capacity, cycle count, charge state and condition — the full picture Apple shows in pieces."
          />
          <SensorCard
            iconBg="rgba(191,90,242,0.14)"
            icon={<ChipIcon size={20} color="#BF5AF2" strokeWidth={1.8} />}
            value={vitals.gpuLoad}
            title="CPU & GPU load"
            body="Per-core utilization and integrated GPU activity, charted over time with Swift Charts."
          />
          <SensorCard
            iconBg="rgba(255,159,10,0.14)"
            icon={
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#FF9F0A" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <path d="M13 2L4.5 13.5H11l-1 8.5L19.5 10H13l1-8z" fill="#FF9F0A" stroke="none" />
              </svg>
            }
            value={vitals.power}
            title="Power draw"
            body="Package wattage in real time, so you can see exactly what a workload costs in heat."
          />
          <SensorCard
            iconBg="rgba(100,210,255,0.14)"
            icon={
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#64D2FF" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <line x1="4" y1="6" x2="20" y2="6" />
                <line x1="4" y1="12" x2="20" y2="12" />
                <line x1="4" y1="18" x2="14" y2="18" />
              </svg>
            }
            value="↓ sorted"
            title="Top processes"
            body="See what's actually heating your Mac, ranked by CPU and energy impact."
          />
        </div>
      </div>
    </section>
  )
}
