import { channels, type Channel, MUTE } from '../../lib/channels'
import { useLiveVitals } from '../../lib/useLiveVitals'
import { flatPath, wavePath } from '../../lib/waves'

export interface TraceProps {
  channel: Channel
  beats: number
  width: number
  height: number
  className?: string
  flat?: boolean
}

export function Trace({ channel, beats, width, height, className = '', flat = false }: TraceProps) {
  const vitals = useLiveVitals()
  const spec = channels[channel]
  const d = flat ? flatPath(width, height) : wavePath(spec.wave, vitals.levels[channel].slice(-beats), width, height, vitals.tick + beats)
  const stroke = flat ? MUTE : spec.stroke
  return (
    <svg viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" className={`block overflow-visible ${className}`} aria-hidden="true" data-trace={channel}>
      {flat ? null : <path d={d} fill="none" stroke={stroke} strokeOpacity={0.16} strokeWidth={5} strokeLinejoin="round" strokeLinecap="round" />}
      <path d={d} fill="none" stroke={stroke} strokeWidth={1.6} strokeLinejoin="round" strokeLinecap="round" />
      {flat || spec.wave === 'bars' ? null : (
        <path d={d} fill="none" stroke="#fff" strokeWidth={1.8} pathLength={1} strokeDasharray="0.08 1" strokeDashoffset={-0.92} strokeLinejoin="round" strokeLinecap="round" />
      )}
    </svg>
  )
}
