// SVG icons traced 1:1 from the design prototype.

export function HeartbeatIcon({ size, sharp = false, strokeWidth }: { size: number; sharp?: boolean; strokeWidth?: number }) {
  // The nav/download mark uses a taller pulse than the menu-bar/footer mark.
  const points = sharp
    ? '1,12 6,12 8,12 9.4,5 11,19 12.8,9.5 14.5,14 16,12 23,12'
    : '1,12 6,12 8,12 9.4,6 11,18 12.8,10 14.5,14 16,12 23,12'
  return (
    <svg width={size} height={size} viewBox="0 0 24 24">
      <polyline
        points={points}
        fill="none"
        stroke="#FF453A"
        strokeWidth={strokeWidth ?? (sharp ? 1.7 : 1.8)}
        strokeLinejoin="round"
        strokeLinecap="round"
      />
    </svg>
  )
}

export function LogoMark({ box, radius, icon }: { box: number; radius: number; icon: number }) {
  return (
    <div
      style={{
        width: box,
        height: box,
        borderRadius: radius,
        background: 'linear-gradient(160deg, #2a2a2e, #161618)',
        border: '1px solid rgba(255,255,255,0.12)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        boxShadow: '0 2px 8px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.12)',
      }}
    >
      <HeartbeatIcon size={icon} sharp />
    </div>
  )
}

export function FanIcon({ size, color, strokeWidth = 1.7 }: { size: number; color: string; strokeWidth?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="2.2" />
      <path d="M12 9.8c2.5-3 0-7 0-7s-1.5 3.5 0 7zM14.2 12c3 2.5 7 0 7 0s-3.5-1.5-7 0zM12 14.2c-2.5 3 0 7 0 7s1.5-3.5 0-7zM9.8 12c-3-2.5-7 0-7 0s3.5 1.5 7 0z" />
    </svg>
  )
}

export function ChipIcon({ size, color, strokeWidth = 1.7 }: { size: number; color: string; strokeWidth?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round">
      <rect x="6" y="6" width="12" height="12" rx="2" />
      <path d="M9 2v2M12 2v2M15 2v2M9 20v2M12 20v2M15 20v2M2 9h2M2 12h2M2 15h2M20 9h2M20 12h2M20 15h2" />
    </svg>
  )
}

export function MemoryIcon({ size, color, strokeWidth = 1.7 }: { size: number; color: string; strokeWidth?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="7" width="18" height="10" rx="2" />
      <path d="M7 7V5M11 7V5M15 7V5M7 19v-2M11 19v-2M15 19v-2" />
    </svg>
  )
}

export function ThermoIcon({ size, color, strokeWidth = 1.7 }: { size: number; color: string; strokeWidth?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round">
      <path d="M14 14.76V5a2 2 0 0 0-4 0v9.76a4 4 0 1 0 4 0z" />
    </svg>
  )
}

export function CheckIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="#32D74B"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      style={{ marginTop: 1, flexShrink: 0 }}
    >
      <path d="M20 6L9 17l-5-5" />
    </svg>
  )
}
