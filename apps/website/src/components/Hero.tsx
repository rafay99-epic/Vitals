import type { LiveVitals } from '../lib/useLiveVitals'
import { MemoryIcon, FanIcon } from './icons'
import { REPO_URL } from '../lib/links'

const mono = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"

function MetricCard({
  label,
  value,
  valueColor,
  gradientId,
  gradientColor,
  gradientFrom,
  gradientTo,
  area,
  line,
  lineColor,
}: {
  label: string
  value: string
  valueColor: string
  gradientId: string
  gradientColor: string
  gradientFrom: string
  gradientTo: string
  area: string
  line: string
  lineColor: string
}) {
  return (
    <div style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.07)', borderRadius: 12, padding: '9px 10px 0', overflow: 'hidden' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 5 }}>
        <span style={{ fontSize: 12, color: 'rgba(235,235,245,0.6)' }}>{label}</span>
        <span style={{ fontSize: 13, fontWeight: 600, color: valueColor }}>{value}</span>
      </div>
      <svg width="100%" height="40" viewBox="0 0 100 40" preserveAspectRatio="none" style={{ display: 'block' }}>
        <defs>
          <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor={gradientColor} stopOpacity={gradientFrom} />
            <stop offset="1" stopColor={gradientColor} stopOpacity={gradientTo} />
          </linearGradient>
        </defs>
        <polyline points={area} fill={`url(#${gradientId})`} stroke="none" />
        <polyline points={line} fill="none" stroke={lineColor} strokeWidth="1.6" strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
      </svg>
    </div>
  )
}

function segStyle(active: boolean): React.CSSProperties {
  return {
    textAlign: 'center',
    padding: '11px 0',
    borderRadius: 10,
    fontSize: 14,
    fontWeight: 500,
    color: active ? '#56AFFF' : 'rgba(235,235,245,0.55)',
    background: active ? 'rgba(10,153,255,0.16)' : 'rgba(255,255,255,0.05)',
    border: active ? '1px solid rgba(10,153,255,0.4)' : '1px solid rgba(255,255,255,0.08)',
  }
}

const actionBtn: React.CSSProperties = {
  padding: '9px 16px',
  borderRadius: 9,
  fontSize: 14,
  fontWeight: 500,
  background: 'rgba(255,255,255,0.07)',
  border: '1px solid rgba(255,255,255,0.1)',
}

export default function Hero({ vitals }: { vitals: LiveVitals }) {
  return (
    <section style={{ position: 'relative', padding: '168px 24px 40px', display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
      <div
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          gap: 8,
          padding: '6px 13px 6px 9px',
          borderRadius: 100,
          background: 'rgba(255,255,255,0.05)',
          border: '1px solid rgba(255,255,255,0.1)',
          fontSize: 12.5,
          color: 'rgba(235,235,245,0.72)',
          marginBottom: 26,
        }}
      >
        <span style={{ display: 'inline-flex', width: 7, height: 7, borderRadius: '50%', background: '#32D74B', boxShadow: '0 0 8px #32D74B', animation: 'vt-pulse 2s ease-in-out infinite' }} />
        Native menu-bar app · Apple Silicon
      </div>
      <h1
        style={{
          fontSize: 72,
          lineHeight: 1.02,
          fontWeight: 680,
          letterSpacing: '-0.035em',
          margin: '0 0 22px',
          maxWidth: '14ch',
          background: 'linear-gradient(180deg, #ffffff 30%, rgba(255,255,255,0.66))',
          WebkitBackgroundClip: 'text',
          backgroundClip: 'text',
          color: 'transparent',
        }}
      >
        Your Mac has a dashboard. Apple just hid it.
      </h1>
      <p style={{ fontSize: 19, lineHeight: 1.5, color: 'rgba(235,235,245,0.6)', margin: '0 0 34px', maxWidth: '52ch' }}>
        Vitals reads the temperature of your chip, the speed of your fans, and the health of your battery — straight from the hardware — and shows it
        in a window that looks like Apple built it.
      </p>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <a
          href="#download"
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 9,
            fontSize: 15,
            fontWeight: 590,
            color: '#fff',
            textDecoration: 'none',
            padding: '13px 22px',
            borderRadius: 13,
            background: 'linear-gradient(180deg, #1a8cff, #0a72e8)',
            boxShadow: '0 6px 22px rgba(10,132,255,0.42), inset 0 1px 0 rgba(255,255,255,0.25)',
          }}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="#fff">
            <path d="M12 3v11m0 0l-4-4m4 4l4-4M5 19h14" stroke="#fff" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          Download for macOS
        </a>
        <a
          href={REPO_URL}
          target="_blank"
          rel="noreferrer"
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 8,
            fontSize: 15,
            fontWeight: 500,
            color: '#f5f5f7',
            textDecoration: 'none',
            padding: '13px 20px',
            borderRadius: 13,
            background: 'rgba(255,255,255,0.06)',
            border: '1px solid rgba(255,255,255,0.12)',
          }}
        >
          View source
        </a>
      </div>
      <p style={{ fontSize: 12.5, color: 'rgba(235,235,245,0.38)', margin: '18px 0 0' }}>Free · Open source · Universal · Requires macOS 15 or later</p>

      {/* ===== PRODUCT MOCK: menu-bar dropdown ===== */}
      <div style={{ position: 'relative', marginTop: 56, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <div
          style={{
            position: 'absolute',
            top: 30,
            width: 560,
            height: 480,
            background:
              'radial-gradient(circle at 30% 30%, rgba(255,146,48,0.16), transparent 55%), radial-gradient(circle at 75% 40%, rgba(0,170,255,0.16), transparent 55%), radial-gradient(circle at 50% 80%, rgba(136,120,255,0.14), transparent 55%)',
            filter: 'blur(50px)',
            zIndex: 0,
          }}
        />

        {/* faux menu-bar item */}
        <div
          style={{
            position: 'relative',
            zIndex: 2,
            display: 'flex',
            alignItems: 'center',
            gap: 7,
            padding: '5px 11px',
            marginBottom: 12,
            background: 'rgba(255,255,255,0.07)',
            border: '1px solid rgba(255,255,255,0.1)',
            borderRadius: 8,
            backdropFilter: 'blur(20px)',
            WebkitBackdropFilter: 'blur(20px)',
          }}
        >
          <svg width="14" height="14" viewBox="0 0 24 24">
            <polyline points="1,12 6,12 8,12 9.4,6 11,18 12.8,10 14.5,14 16,12 23,12" fill="none" stroke="#FF453A" strokeWidth="1.8" strokeLinejoin="round" strokeLinecap="round" />
          </svg>
          <span style={{ fontFamily: mono, fontSize: 12.5, fontWeight: 500, color: '#f5f5f7' }}>{vitals.avgCpu}°</span>
        </div>

        {/* ===== REAL VITALS MENU-BAR DROPDOWN ===== */}
        <div
          style={{
            position: 'relative',
            zIndex: 2,
            width: 428,
            padding: 0,
            overflow: 'hidden',
            background: 'linear-gradient(180deg, rgba(38,40,46,0.82), rgba(22,24,29,0.88))',
            backdropFilter: 'blur(60px) saturate(180%)',
            WebkitBackdropFilter: 'blur(60px) saturate(180%)',
            border: '1px solid rgba(255,255,255,0.13)',
            borderRadius: 20,
            boxShadow: '0 44px 100px -26px rgba(0,0,0,0.88), 0 2px 8px rgba(0,0,0,0.4), inset 0 1px 0 rgba(255,255,255,0.13)',
            textAlign: 'left',
            animation: 'vt-float 7s ease-in-out infinite',
          }}
        >
          {/* bokeh wallpaper bleed */}
          <div style={{ position: 'absolute', top: -10, left: 18, width: 70, height: 70, borderRadius: '50%', background: '#FF9230', opacity: 0.22, filter: 'blur(26px)' }} />
          <div style={{ position: 'absolute', top: -6, left: 220, width: 60, height: 60, borderRadius: '50%', background: '#00AAFF', opacity: 0.18, filter: 'blur(26px)' }} />
          <div style={{ position: 'absolute', top: 4, left: 320, width: 60, height: 60, borderRadius: '50%', background: '#34D85F', opacity: 0.16, filter: 'blur(26px)' }} />

          <div style={{ position: 'relative', zIndex: 1, padding: '18px 18px 16px' }}>
            {/* header */}
            <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 16 }}>
              <div>
                <div style={{ fontSize: 21, fontWeight: 700, letterSpacing: '-0.02em', lineHeight: 1.1 }}>Apple M4</div>
                <div style={{ fontSize: 13, fontWeight: 500, color: '#34D85F', marginTop: 3 }}>Nominal thermal pressure</div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 2, justifyContent: 'flex-end' }}>
                  <span style={{ fontSize: 29, fontWeight: 700, color: '#34D85F', letterSpacing: '-0.02em' }}>{vitals.avgCpu}</span>
                  <span style={{ fontSize: 17, fontWeight: 600, color: '#34D85F' }}>°C</span>
                </div>
                <div style={{ fontSize: 12, color: 'rgba(235,235,245,0.45)', marginTop: 1 }}>avg CPU</div>
              </div>
            </div>

            {/* 3 mini metric cards */}
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 9 }}>
              <MetricCard
                label="Temp"
                value={`${vitals.tempVal}°`}
                valueColor="#FF9F4A"
                gradientId="vt-o"
                gradientColor="#FF9230"
                gradientFrom="0.45"
                gradientTo="0"
                area={vitals.tempArea}
                line={vitals.tempLine}
                lineColor="#FF9230"
              />
              <MetricCard
                label="CPU"
                value={vitals.cpuPct}
                valueColor="#2AB0FF"
                gradientId="vt-b"
                gradientColor="#00AAFF"
                gradientFrom="0.42"
                gradientTo="0"
                area={vitals.cpuPctArea}
                line={vitals.cpuLine}
                lineColor="#00AAFF"
              />
              <MetricCard
                label="Memory"
                value={vitals.memVal}
                valueColor="#9A8CFF"
                gradientId="vt-p"
                gradientColor="#8878FF"
                gradientFrom="0.5"
                gradientTo="0.08"
                area={vitals.memArea}
                line={vitals.memLine}
                lineColor="#9A8CFF"
              />
            </div>

            {/* memory + status row */}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 14 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <MemoryIcon size={17} color="rgba(235,235,245,0.55)" strokeWidth={1.6} />
                <span style={{ fontSize: 14, color: 'rgba(235,235,245,0.82)' }}>12.4 / 16 GB · swap 6.2 GB</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ width: 9, height: 9, borderRadius: '50%', background: '#34D85F' }} />
                <span style={{ fontSize: 14, color: 'rgba(235,235,245,0.82)' }}>Normal</span>
              </div>
            </div>

            <div style={{ height: 1, background: 'rgba(255,255,255,0.09)', margin: '14px 0' }} />

            {/* fan row */}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <FanIcon size={18} color="rgba(235,235,245,0.75)" strokeWidth={1.7} />
                <span style={{ fontSize: 17, fontWeight: 600 }}>0 rpm</span>
              </div>
              <span style={{ fontSize: 14, color: 'rgba(235,235,245,0.5)' }}>Automatic</span>
            </div>

            {/* fan mode segmented */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8, marginTop: 12 }}>
              <div style={segStyle(true)}>Auto</div>
              <div style={segStyle(false)}>Quiet</div>
              <div style={segStyle(false)}>Med</div>
              <div style={segStyle(false)}>Max</div>
            </div>

            {/* bottom actions */}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 16 }}>
              <div style={actionBtn}>Open Vitals</div>
              <div style={{ display: 'flex', gap: 8 }}>
                <div style={actionBtn}>Settings</div>
                <div style={actionBtn}>Quit</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
