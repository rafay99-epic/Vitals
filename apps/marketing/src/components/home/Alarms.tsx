import { wavePath } from '../../lib/waves'
import { BeatSwitch } from '../ui/BeatSwitch'
import { Reveal, useSeen } from '../ui/Reveal'
import { Em, Lede, SectionTitle } from '../ui/text'

const NIGHT = [0.22, 0.24, 0.21, 0.23, 0.22, 0.24, 0.22, 0.23, 0.3, 0.37, 0.44, 0.51, 0.58, 0.65, 0.72, 0.79, 0.86, 0.93, 1, 0.98, 0.9, 0.7, 0.5, 0.38, 0.3, 0.26, 0.24, 0.22, 0.23, 0.22]

const RULES = [
  { name: 'Agent crowd', rule: 'Six or more agent processes', on: true },
  { name: 'Pressure critical', rule: 'Memory pressure critical for 10 s', on: true },
  { name: 'Swap climbing', rule: 'Swap above 4 GB and growing', on: true },
  { name: 'Running hot', rule: 'Thermal pressure serious or worse', on: true },
  { name: 'Pulse racing', rule: 'CPU above 90% for a minute', on: false },
  { name: 'Emulators fighting', rule: 'Two or more emulators under pressure', on: true },
] as const

function Timeline() {
  const [ref, seen] = useSeen<HTMLDivElement>()
  return (
    <div ref={ref} className="rise relative mt-11 h-[200px] border-y border-line md:h-[240px]">
      <svg viewBox="0 0 1168 200" preserveAspectRatio="none" className={`trace-draw absolute inset-x-0 top-5 h-[160px] w-full md:h-[200px] ${seen ? 'is-drawn' : ''}`} aria-hidden="true">
        <defs>
          <linearGradient id="guard-night" gradientUnits="userSpaceOnUse" x1="0" x2="1168" y1="0" y2="0">
            <stop offset="0" className="[stop-color:var(--color-pulse)]" />
            <stop offset=".4" className="[stop-color:var(--color-pulse)]" />
            <stop offset=".55" className="[stop-color:var(--color-alarm-high)]" />
            <stop offset=".7" className="[stop-color:var(--color-alarm-high)]" />
            <stop offset=".78" className="[stop-color:var(--color-pulse)]" />
            <stop offset="1" className="[stop-color:var(--color-pulse)]" />
          </linearGradient>
        </defs>
        <path d={wavePath('ecg', NIGHT, 1168, 200)} pathLength={1} fill="none" stroke="url(#guard-night)" strokeWidth={1.8} strokeLinejoin="round" />
      </svg>
      <span className="absolute left-0 top-3.5 border-l border-line3 px-2 py-1 font-mono text-[10.5px] text-dim">02:41 · Resting · 23% CPU</span>
      <span className="absolute left-[34%] top-3.5 hidden bg-alarm-high px-2 py-1 font-mono-medium text-[10.5px] text-bg sm:block md:left-[52%]">02:58 · Six agents holding 2.2 GB</span>
      <span className="absolute bottom-3 right-0 border-l border-pulse px-2 py-1 font-mono text-[10.5px] text-pulse md:bottom-auto md:left-[75%] md:right-auto md:top-3.5">03:02 · Calmed · 6 throttled</span>
    </div>
  )
}

export function Alarms() {
  return (
    <Reveal id="guard" className="border-t border-line px-5 py-16 md:px-16 md:py-24">
      <div className="grid items-start gap-6 lg:grid-cols-[380px_1fr] lg:gap-16">
        <SectionTitle>
          Alarms <Em>that act.</Em>
        </SectionTitle>
        <Lede className="rise lg:pt-3">
          Pressure Guard watches for the moments a Mac starts to drown: agents piling up, swap growing, emulators fighting for memory. When a rule trips it raises an alarm, and with one tap it calms the group. Undo is always one tap away.
        </Lede>
      </div>
      <Timeline />
      <div className="mt-9 grid gap-x-12 md:grid-cols-2">
        {RULES.map((rule) => (
          <div key={rule.name} className="rise flex items-center justify-between gap-4 border-b border-line py-3">
            <div>
              <b className="block font-serif text-[22px] font-normal">{rule.name}</b>
              <span className="mt-0.5 block font-mono text-[10.5px] text-dim">{rule.rule}</span>
            </div>
            <BeatSwitch label={`${rule.name} rule`} initial={rule.on} />
          </div>
        ))}
      </div>
    </Reveal>
  )
}
