import type { ReactNode } from 'react'
import { ChipIcon, FanIcon, MemoryIcon, ThermoIcon } from './icons'

const mono = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"

// The five tabs a fresh install leads with, then the deep-dives and tools that
// are one switch away (Settings → Tabs) — mirrors the real default nav (#43).
const SHOWN_TABS = ['Dashboard', 'Processes', 'History', 'Battery', 'Storage']
const HIDDEN_TABS = ['GPU', 'Health', 'Applications', 'Login Items', 'Cleanup']

function Card({ tint, label, title, children }: { tint: string; label: string; title: string; children: ReactNode }) {
  return (
    <div style={{ background: '#131922', border: '1px solid rgba(255,255,255,0.06)', borderRadius: 16, padding: 20, display: 'flex', flexDirection: 'column' }}>
      <div style={{ fontSize: 12, fontWeight: 600, letterSpacing: '0.04em', color: tint, marginBottom: 8 }}>{label}</div>
      <div style={{ fontSize: 17, fontWeight: 640, letterSpacing: '-0.02em', marginBottom: 16 }}>{title}</div>
      {children}
    </div>
  )
}

// MARK: History — timeline with range zoom + Low/Avg/Peak summary (#40)

const RANGES = ['Hour', 'Day', 'Week', 'All']
// A believable thermal trace; static geometry, not a faked live reading.
const TRACE =
  '0,150 40,144 80,150 120,120 160,128 200,96 240,108 280,72 320,90 360,60 400,76 440,52 480,70 520,44 560,66 600,40 640,58 680,46 720,62 760,38 800,54 840,42 880,58 920,40 960,52 1000,46'

function HistoryCard() {
  return (
    <Card tint="#2AB0FF" label="HISTORY" title="Every reading, kept and re-readable.">
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 14, flexWrap: 'wrap' }}>
        <div style={{ display: 'flex', gap: 2, padding: 2, borderRadius: 100, background: 'rgba(255,255,255,0.06)' }}>
          {RANGES.map((r) => (
            <span
              key={r}
              style={{
                fontSize: 11.5,
                fontWeight: 500,
                padding: '3px 11px',
                borderRadius: 100,
                color: r === 'Day' ? '#f5f5f7' : 'rgba(235,235,245,0.5)',
                background: r === 'Day' ? 'rgba(255,255,255,0.12)' : 'transparent',
              }}
            >
              {r}
            </span>
          ))}
        </div>
        <div style={{ flex: 1 }} />
        <div style={{ display: 'flex', gap: 2, padding: 2, borderRadius: 100, background: 'rgba(255,255,255,0.06)', fontSize: 11 }}>
          <span style={{ padding: '3px 9px', borderRadius: 100, background: 'rgba(255,255,255,0.12)' }}>Temp</span>
          <span style={{ padding: '3px 9px', color: 'rgba(235,235,245,0.5)' }}>CPU</span>
          <span style={{ padding: '3px 9px', color: 'rgba(235,235,245,0.5)' }}>GPU</span>
          <span style={{ padding: '3px 9px', color: 'rgba(235,235,245,0.5)' }}>Mem</span>
        </div>
      </div>
      <div style={{ position: 'relative', height: 150, marginBottom: 14 }}>
        <svg width="100%" height="100%" viewBox="0 0 1000 160" preserveAspectRatio="none" style={{ display: 'block', overflow: 'visible' }}>
          <line x1="0" y1="40" x2="1000" y2="40" stroke="rgba(255,255,255,0.06)" />
          <line x1="0" y1="100" x2="1000" y2="100" stroke="rgba(255,255,255,0.06)" />
          <line x1="0" y1="159" x2="1000" y2="159" stroke="rgba(255,255,255,0.1)" />
          <polyline points={`0,160 ${TRACE} 1000,160`} fill="rgba(42,176,255,0.10)" stroke="none" />
          <polyline points={TRACE} fill="none" stroke="#2AB0FF" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
        </svg>
      </div>
      <div style={{ display: 'flex', gap: 18, marginBottom: 14 }}>
        {[
          ['Low', '34°'],
          ['Average', '47°'],
          ['Peak', '71°'],
        ].map(([k, v]) => (
          <div key={k}>
            <div style={{ fontSize: 11, color: 'rgba(235,235,245,0.4)' }}>{k}</div>
            <div style={{ fontFamily: mono, fontSize: 17, fontWeight: 600, marginTop: 2 }}>{v}</div>
          </div>
        ))}
        <div style={{ flex: 1 }} />
        <div style={{ alignSelf: 'flex-end', fontSize: 11, color: 'rgba(235,235,245,0.4)' }}>1,440 points · 24 h</div>
      </div>
      <div style={{ marginTop: 'auto', fontSize: 12.5, color: 'rgba(235,235,245,0.5)', lineHeight: 1.45 }}>
        Logging is off until you turn it on. When it's on, Vitals writes a plain <span style={{ fontFamily: mono, color: 'rgba(235,235,245,0.7)' }}>history.csv</span> you can
        zoom by Hour / Day / Week / All — and export to CSV or JSON whenever you want.
      </div>
    </Card>
  )
}

// MARK: Custom alerts — the user-defined rule engine (#39)

const RULES = [
  { text: 'CPU temperature above 90 °C for 2 min', on: true },
  { text: 'Free disk below 10 GB', on: true },
  { text: 'Fan speed equals 0 rpm', on: false },
  { text: 'ffmpeg CPU above 80 % for 5 min', on: true },
]

function Switch({ on }: { on: boolean }) {
  return (
    <span
      style={{
        width: 30,
        height: 18,
        borderRadius: 100,
        background: on ? '#32D74B' : 'rgba(255,255,255,0.16)',
        position: 'relative',
        flexShrink: 0,
        transition: 'background 0.2s',
      }}
    >
      <span style={{ position: 'absolute', top: 2, left: on ? 14 : 2, width: 14, height: 14, borderRadius: '50%', background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.4)' }} />
    </span>
  )
}

function AlertsCard() {
  return (
    <Card tint="#FF9F4A" label="THRESHOLD ALERTS" title="Tell it what you want to know about.">
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {RULES.map((rule) => (
          <div
            key={rule.text}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 10,
              padding: '10px 12px',
              borderRadius: 10,
              background: 'rgba(255,255,255,0.04)',
              border: '1px solid rgba(255,255,255,0.07)',
            }}
          >
            <span style={{ fontSize: 12.5, color: rule.on ? '#f5f5f7' : 'rgba(235,235,245,0.45)', flex: 1, lineHeight: 1.35 }}>{rule.text}</span>
            <Switch on={rule.on} />
          </div>
        ))}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 6,
            padding: '9px 12px',
            borderRadius: 10,
            border: '1px dashed rgba(255,255,255,0.16)',
            fontSize: 12.5,
            color: 'rgba(235,235,245,0.5)',
          }}
        >
          <span style={{ fontSize: 15, lineHeight: 1 }}>+</span> Add an alert
        </div>
      </div>
      <div style={{ marginTop: 16, fontSize: 12.5, color: 'rgba(235,235,245,0.5)', lineHeight: 1.45 }}>
        Build your own rules on temperature, CPU, GPU, memory, fans, free disk, battery, or any single process — with a sustain window so a one-second
        spike never nags you. Notified once per problem, never per tick.
      </div>
    </Card>
  )
}

// MARK: Health verdict (#37)

const SIGNALS = [
  ['Thermal state', 'Nominal'],
  ['Memory pressure', 'Normal'],
  ['Hottest sensor', '41°'],
  ['Fans', 'Automatic'],
  ['SoC power', '8.4 W'],
]

function HealthCard() {
  return (
    <Card tint="#34D85F" label="HEALTH" title="One honest verdict.">
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 18 }}>
        <div style={{ width: 52, height: 52, borderRadius: 14, background: 'rgba(50,215,75,0.14)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#32D74B" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 2l8 4v5c0 5-3.5 8.5-8 11-4.5-2.5-8-6-8-11V6z" />
            <path d="M9 12l2 2 4-4" />
          </svg>
        </div>
        <div>
          <div style={{ fontSize: 22, fontWeight: 680, letterSpacing: '-0.02em' }}>Running cool</div>
          <div style={{ fontSize: 13, color: 'rgba(235,235,245,0.5)', marginTop: 2 }}>Not throttling · composed from real signals</div>
        </div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 1, borderRadius: 10, overflow: 'hidden', border: '1px solid rgba(255,255,255,0.07)' }}>
        {SIGNALS.map(([k, v], i) => (
          <div
            key={k}
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '9px 12px',
              background: 'rgba(255,255,255,0.035)',
              borderTop: i > 0 ? '1px solid rgba(255,255,255,0.05)' : 'none',
            }}
          >
            <span style={{ fontSize: 12.5, color: 'rgba(235,235,245,0.6)' }}>{k}</span>
            <span style={{ fontSize: 12.5, fontFamily: mono, color: '#f5f5f7' }}>{v}</span>
          </div>
        ))}
      </div>
      <div style={{ marginTop: 16, fontSize: 12.5, color: 'rgba(235,235,245,0.5)', lineHeight: 1.45 }}>
        Reads macOS's own throttling state instead of guessing from clock speeds. One tap copies a full diagnostics snapshot to your clipboard.
      </div>
    </Card>
  )
}

// MARK: Processes (#35)

const PROCS = [
  { letter: 'B', from: '#FF7A45', to: '#E0494B', name: 'Brave Browser', sub: '58 processes', ram: '4.2 GB', cpu: '12%' },
  { letter: 'X', from: '#2AB0FF', to: '#0A5FCC', name: 'Xcode', sub: '9 processes', ram: '3.1 GB', cpu: '34%' },
  { letter: 'F', from: '#BF5AF2', to: '#7A2FB8', name: 'Figma', sub: '6 processes', ram: '1.8 GB', cpu: '6%' },
  { letter: 'S', from: '#34D85F', to: '#0E8A4A', name: 'Spotify', sub: '4 processes', ram: '612 MB', cpu: '2%' },
]

function ProcessesCard() {
  return (
    <Card tint="#BF5AF2" label="PROCESSES" title="What's actually using your Mac.">
      <div style={{ display: 'flex', flexDirection: 'column', gap: 1, borderRadius: 10, overflow: 'hidden', border: '1px solid rgba(255,255,255,0.07)' }}>
        <div style={{ display: 'flex', alignItems: 'center', padding: '7px 12px', background: 'rgba(255,255,255,0.05)', fontSize: 10, color: 'rgba(235,235,245,0.4)', letterSpacing: '0.03em' }}>
          <span style={{ flex: 1 }}>APP</span>
          <span style={{ width: 64, textAlign: 'right' }}>MEMORY</span>
          <span style={{ width: 44, textAlign: 'right' }}>CPU</span>
        </div>
        {PROCS.map((p, i) => (
          <div
            key={p.name}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 9,
              padding: '8px 12px',
              background: 'rgba(255,255,255,0.035)',
              borderTop: i > 0 ? '1px solid rgba(255,255,255,0.05)' : 'none',
            }}
          >
            <span
              style={{
                width: 22,
                height: 22,
                borderRadius: 6,
                background: `linear-gradient(160deg, ${p.from}, ${p.to})`,
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 11,
                fontWeight: 700,
                color: '#fff',
                flexShrink: 0,
              }}
            >
              {p.letter}
            </span>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 12, fontWeight: 500 }}>{p.name}</div>
              <div style={{ fontSize: 10, color: 'rgba(235,235,245,0.38)' }}>{p.sub}</div>
            </div>
            <span style={{ width: 64, textAlign: 'right', fontSize: 11.5, fontFamily: mono, color: 'rgba(235,235,245,0.7)' }}>{p.ram}</span>
            <span style={{ width: 44, textAlign: 'right', fontSize: 11.5, fontFamily: mono, color: 'rgba(235,235,245,0.7)' }}>{p.cpu}</span>
          </div>
        ))}
      </div>
      <div style={{ marginTop: 16, fontSize: 12.5, color: 'rgba(235,235,245,0.5)', lineHeight: 1.45 }}>
        An app's dozens of helpers fold into one row with real totals — the
        <span style={{ color: 'rgba(235,235,245,0.7)' }}> "how much RAM is this using, and quit it" </span>
        Activity Monitor makes clumsy. One-click Quit; only your own processes, and Vitals never lists itself.
      </div>
    </Card>
  )
}

export default function Monitoring() {
  return (
    <section id="monitor" style={{ position: 'relative', padding: '80px 24px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      <div style={{ width: '100%', maxWidth: 1080 }}>
        <div style={{ textAlign: 'center', marginBottom: 36 }}>
          <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#2AB0FF', marginBottom: 14 }}>DEEPER THAN A DASHBOARD</div>
          <h2 className="text-[32px] md:text-[44px]" style={{ fontWeight: 670, letterSpacing: '-0.035em', margin: '0 auto 16px', lineHeight: 1.06, maxWidth: '17ch' }}>
            Go as deep as you want to.
          </h2>
          <p style={{ fontSize: 16, lineHeight: 1.5, color: 'rgba(235,235,245,0.55)', margin: '0 auto', maxWidth: '58ch' }}>
            Vitals opens as a hardware monitor — five tabs, like Activity Monitor. The deep-dives and tools are one switch away when you want them,
            never crowding the first launch.
          </p>
        </div>

        {/* Tab strip — the monitoring-first default nav (#43) */}
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12, marginBottom: 40 }}>
          <div style={{ display: 'flex', gap: 4, padding: 4, borderRadius: 100, background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.08)', flexWrap: 'wrap', justifyContent: 'center' }}>
            {SHOWN_TABS.map((t, i) => (
              <span
                key={t}
                style={{
                  fontSize: 13,
                  fontWeight: 500,
                  padding: '6px 15px',
                  borderRadius: 100,
                  color: i === 0 ? '#f5f5f7' : 'rgba(235,235,245,0.6)',
                  background: i === 0 ? 'rgba(255,255,255,0.12)' : 'transparent',
                }}
              >
                {t}
              </span>
            ))}
          </div>
          <div style={{ fontSize: 12.5, color: 'rgba(235,235,245,0.42)' }}>
            {HIDDEN_TABS.join(' · ')} — one switch away in Settings → Tabs
          </div>
        </div>

        {/* Feature mocks */}
        <div className="grid grid-cols-1 lg:grid-cols-2" style={{ gap: 14 }}>
          <HistoryCard />
          <AlertsCard />
          <ProcessesCard />
          <HealthCard />
        </div>

        {/* Subsystem readouts the dedicated tabs add */}
        <div className="grid grid-cols-2 lg:grid-cols-4" style={{ gap: 12, marginTop: 14 }}>
          {[
            { icon: <ChipIcon size={18} color="#BF5AF2" strokeWidth={1.8} />, title: 'GPU', body: 'Device / renderer / tiler load, unified-memory working set, core count, live watts.' },
            { icon: <ThermoIcon size={18} color="#FF9F4A" strokeWidth={1.8} />, title: 'Battery', body: 'Max vs design capacity, cycles, condition, live voltage / current / temperature.' },
            { icon: <MemoryIcon size={18} color="#34D85F" strokeWidth={1.8} />, title: 'Storage', body: 'Capacity overview and a disk analyzer that shows where the space went.' },
            { icon: <FanIcon size={18} color="#00D8F0" strokeWidth={1.7} />, title: 'Diagnostics', body: 'Copy a full plain-text snapshot of every reading — read-only, nothing faked.' },
          ].map((s) => (
            <div key={s.title} style={{ background: 'rgba(255,255,255,0.035)', border: '1px solid rgba(255,255,255,0.07)', borderRadius: 14, padding: 16 }}>
              <div style={{ width: 32, height: 32, borderRadius: 8, background: 'rgba(255,255,255,0.05)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 12 }}>{s.icon}</div>
              <div style={{ fontSize: 14, fontWeight: 600, marginBottom: 4 }}>{s.title}</div>
              <div style={{ fontSize: 12.5, color: 'rgba(235,235,245,0.5)', lineHeight: 1.45 }}>{s.body}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
