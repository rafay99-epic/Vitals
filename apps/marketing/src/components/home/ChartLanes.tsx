import type { Channel } from '../../lib/channels'
import { channels } from '../../lib/channels'
import { useLiveVitals, type Vitals } from '../../lib/useLiveVitals'
import { Reveal } from '../ui/Reveal'
import { Em, Lede, Tag, SectionTitle } from '../ui/text'
import { Trace } from '../ui/Trace'

interface Lane {
  channel: Channel
  beats: number
  value: (vitals: Vitals) => string
  unit: string
}

const LANES: Lane[] = [
  { channel: 'pulse', beats: 16, value: (v) => String(Math.round(v.cpu)), unit: '%' },
  { channel: 'eeg', beats: 18, value: (v) => String(Math.round(v.gpu)), unit: '%' },
  { channel: 'press', beats: 16, value: (v) => v.mem.toFixed(1), unit: 'GB' },
  { channel: 'temp', beats: 9, value: (v) => `${Math.round(v.temp)}°`, unit: '' },
  { channel: 'resp', beats: 20, value: (v) => String(Math.round(v.fans)), unit: 'rpm' },
  { channel: 'oxy', beats: 9, value: (v) => String(v.batt), unit: '%' },
  { channel: 'drip', beats: 48, value: (v) => v.power.toFixed(1), unit: 'W' },
  { channel: 'tele', beats: 70, value: (v) => v.down.toFixed(1), unit: 'MB/s' },
]

const FACTS = [
  ['Channels', '8'],
  ['Logged', 'every 10 s'],
  ['Kept', 'a year, on this Mac'],
  ['Export', 'CSV'],
] as const

export function ChartLanes() {
  const vitals = useLiveVitals()
  return (
    <Reveal id="chart" className="border-t border-line px-5 py-16 md:px-16 md:py-24">
      <div className="grid items-start gap-12 lg:grid-cols-[380px_1fr] lg:gap-16">
        <div className="rise grid content-start gap-5">
          <SectionTitle>
            Every vital, <Em>one chart.</Em>
          </SectionTitle>
          <Lede>Eight channels, each in its own color, each with its plain name underneath. Readings log locally, browse the timeline, export it whenever you want it.</Lede>
          <dl className="m-0 border-t border-line">
            {FACTS.map(([key, value]) => (
              <div key={key} className="flex justify-between border-b border-line py-2.5 font-mono text-[11px]">
                <dt className="text-dim">{key}</dt>
                <dd className="m-0">{value}</dd>
              </div>
            ))}
          </dl>
        </div>
        <div className="rise border-t border-line">
          {LANES.map((lane) => {
            const spec = channels[lane.channel]
            return (
              <div key={lane.channel} className="grid h-[74px] grid-cols-[64px_1fr_92px] items-center gap-3 border-b border-line md:grid-cols-[112px_1fr_120px] md:gap-[18px]">
                <div className={`font-mono-medium text-[10px] leading-[1.35] tracking-[0.08em] ${spec.text}`}>
                  {spec.tag}
                  <span className="block font-mono tracking-normal text-dim">{spec.label}</span>
                </div>
                <Trace channel={lane.channel} beats={lane.beats} width={700} height={56} className="h-14 w-full" />
                <div className={`text-right font-serif text-[32px] leading-none md:text-[44px] ${spec.text}`}>
                  {lane.value(vitals)}
                  {lane.unit === '' ? null : <small className="ml-0.5 font-mono text-[10px]">{lane.unit}</small>}
                </div>
              </div>
            )
          })}
          <Tag className="mt-3 block text-dim">Demo readings, not your Mac</Tag>
        </div>
      </div>
    </Reveal>
  )
}
