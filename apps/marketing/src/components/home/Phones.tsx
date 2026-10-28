import type { ReactNode } from 'react'
import { channels, type Channel } from '../../lib/channels'
import { useLiveVitals } from '../../lib/useLiveVitals'
import { wavePath } from '../../lib/waves'
import { Hold } from '../ui/Hold'
import { Trace } from '../ui/Trace'

const TABS = ['Chart', 'Orders', 'Ward', 'Alarms', 'Record'] as const
type TabName = (typeof TABS)[number]

const GLYPH: Record<TabName, string> = {
  Chart: 'M1 10 H8 L10 13 L14 2 L16 10 H25',
  Orders: 'M3 3 H5 M9 3 H23 M3 8 H5 M9 8 H23 M3 13 H5 M9 13 H17',
  Ward: 'M3 2 V14 M3 10 H23 V14 M6 7 H11',
  Alarms: 'M13 1.5 L23.5 14.5 H2.5 Z M13 6.5 V10',
  Record: 'M6 1 H20 V15 H6 Z M9 5 H17 M9 8 H17 M9 11 H14',
}

function TabBar({ active, alarm = false }: { active: TabName; alarm?: boolean }) {
  return (
    <nav className="mt-auto flex h-20 shrink-0 justify-around border-t border-line px-1.5 pt-2.5" aria-hidden="true">
      {TABS.map((tab) => (
        <span key={tab} className={`relative flex w-16 flex-col items-center gap-1.5 font-mono text-[10px] ${tab === active ? 'text-ink' : 'text-mute'}`}>
          <svg viewBox="0 0 26 16" className="h-4 w-[26px] overflow-visible">
            <path d={GLYPH[tab]} fill="none" className={tab === active ? 'stroke-pulse' : 'stroke-current'} strokeWidth="1.5" strokeLinejoin="round" strokeLinecap="round" />
          </svg>
          {tab}
          {alarm && tab === 'Alarms' ? <i className="absolute right-[18px] top-0 block h-1.5 w-1.5 bg-alarm-high" /> : null}
        </span>
      ))}
    </nav>
  )
}

function Phone({ time, active, alarm, children, label }: { time: string; active: TabName; alarm?: boolean; children: ReactNode; label: string }) {
  return (
    <figure className="m-0 h-[471px] w-[223px] shrink-0 overflow-hidden" aria-label={label}>
      <div className="h-[760px] w-[360px] origin-top-left scale-[0.62] rounded-[50px] border border-line3 bg-bg p-[9px]">
        <div className="relative flex h-full w-full flex-col overflow-hidden rounded-[42px] bg-bg">
          <div className="absolute left-1/2 top-[11px] z-10 h-[30px] w-[104px] -translate-x-1/2 rounded-2xl bg-raise" />
          <div className="flex h-[52px] shrink-0 items-center justify-between px-[30px] pt-2 font-sans-semibold text-[14px]">
            <span>{time}</span>
            <span className="h-[11px] w-6 rounded-[3px] border border-dim p-px">
              <span className="block h-full w-4/5 rounded-[1px] bg-ink" />
            </span>
          </div>
          {children}
          <TabBar active={active} alarm={alarm} />
          <div className="absolute bottom-2 left-1/2 h-1 w-[124px] -translate-x-1/2 rounded-sm bg-ink/90" />
        </div>
      </div>
    </figure>
  )
}

function MiniChannel({ channel, value }: { channel: Channel; value: string }) {
  const spec = channels[channel]
  return (
    <div className="grid h-[88px] grid-cols-[58px_1fr_auto] items-center gap-2.5 border-t border-line pl-[22px] pr-5">
      <div className={`font-mono-medium text-[9.5px] leading-[1.3] tracking-[0.08em] ${spec.text}`}>
        {spec.tag}
        <span className="block font-mono tracking-normal text-dim">{spec.label}</span>
      </div>
      <Trace channel={channel} beats={5} width={150} height={54} className="h-[54px] w-full" />
      <div className={`min-w-[74px] text-right font-serif text-[44px] leading-none ${spec.text}`}>{value}</div>
    </div>
  )
}

export function ChartPhone() {
  const vitals = useLiveVitals()
  return (
    <Phone time="23:41" active="Chart" label="The Chart on a phone">
      <div className="flex justify-between px-[22px] pt-1 font-mono text-[10.5px] text-ink2">
        <span>Rafay's MacBook Pro</span>
        <span className="text-pulse">● live</span>
      </div>
      <div className="px-[22px] pb-3 pt-1.5">
        <b className="block font-serif-italic text-[46px] font-normal leading-none">Resting.</b>
        <span className="mt-1 block font-mono text-[10.5px] text-dim">M4 Pro · macOS 26.1</span>
      </div>
      <MiniChannel channel="pulse" value={String(Math.round(vitals.cpu))} />
      <MiniChannel channel="press" value={vitals.mem.toFixed(1)} />
      <MiniChannel channel="temp" value={`${Math.round(vitals.temp)}°`} />
      <MiniChannel channel="resp" value={String(Math.round(vitals.fans))} />
      <MiniChannel channel="oxy" value={String(vitals.batt)} />
    </Phone>
  )
}

function OrderRow({ label, meta, tone = 'text-ink' }: { label: string; meta: string; tone?: string }) {
  return (
    <div className="flex min-h-14 items-center justify-between border-t border-line px-[22px] py-2.5">
      <b className={`font-serif text-[26px] font-normal ${tone}`}>{label}</b>
      <span className="font-mono text-[10px] text-dim">{meta}</span>
    </div>
  )
}

export function OrdersPhone() {
  return (
    <Phone time="23:42" active="Orders" label="Orders on a phone, try holding Rest">
      <div className="px-[22px] pb-3 pt-1.5">
        <b className="block font-serif-italic text-[46px] font-normal leading-none">Orders.</b>
        <span className="mt-1 block font-mono text-[10.5px] text-dim">Rafay's MacBook Pro</span>
      </div>
      <Hold label="Rest" hint="hold to sleep, display goes first" />
      <OrderRow label="Lights out" meta="display off" />
      <OrderRow label="Lock" meta="now" />
      <OrderRow label="Stay awake" meta="1 h · 4 h · forever" />
      <OrderRow label="Calm the ward" meta="6 agents" tone="text-temp" />
      <OrderRow label="Shut down" meta="needs consent" tone="text-press" />
    </Phone>
  )
}

const BEDS = [
  { name: 'claude', meta: 'Claude Code', cpu: 38, mem: '1.4 GB', seed: 3 },
  { name: 'codex', meta: 'Codex CLI', cpu: 21, mem: '420 MB', seed: 8 },
  { name: 'node', meta: 'MCP servers', cpu: 9, mem: '310 MB', seed: 12 },
  { name: 'cursor-agent', meta: 'Cursor', cpu: 6, mem: '96 MB', seed: 17 },
] as const

function Bed({ index, bed, tick }: { index: number; bed: (typeof BEDS)[number]; tick: number }) {
  const levels = Array.from({ length: 24 }, (_, i) => 0.4 + 0.35 * Math.sin((i + tick + bed.seed) / 2.3) * Math.cos((i + bed.seed) / 5))
  return (
    <div className="grid min-h-[58px] grid-cols-[22px_1fr_56px_48px] items-center gap-2 border-t border-line px-[22px] py-2">
      <span className="font-mono text-[10px] text-mute">{String(index + 1).padStart(2, '0')}</span>
      <div className="grid min-w-0 gap-0.5">
        <b className="truncate font-serif text-[20px] font-normal">{bed.name}</b>
        <span className="truncate font-mono text-[10px] text-dim">{bed.meta}</span>
      </div>
      <svg viewBox="0 0 56 24" className="h-6 w-14" aria-hidden="true">
        <path d={wavePath('step', levels, 56, 24)} fill="none" className="stroke-press" strokeWidth="1.3" />
      </svg>
      <div className="text-right font-serif text-[20px] leading-none">
        {bed.cpu}
        <small className="mt-0.5 block font-mono text-[9.5px] text-dim">{bed.mem}</small>
      </div>
    </div>
  )
}

export function WardPhone() {
  const { tick } = useLiveVitals()
  return (
    <Phone time="02:58" active="Ward" alarm label="An alarm on the Ward">
      <div className="flex items-center gap-3 bg-alarm-high py-3 pl-[22px] pr-[18px] text-bg">
        <div className="flex-1">
          <b className="block font-serif-italic text-[24px] font-normal leading-none">Agents crowding.</b>
          <span className="mt-0.5 block font-mono-medium text-[10.5px]">6 agents · 2.2 GB · pressure critical</span>
        </div>
        <span className="bg-bg px-3.5 py-2 font-sans-medium text-[13px] text-ink">Calm</span>
      </div>
      <div className="flex items-baseline justify-between px-[22px] pb-2 pt-5">
        <b className="font-serif-italic text-[26px] font-normal">Agents</b>
        <span className="font-mono text-[10px] text-dim">6 beds · 2.2 GB</span>
      </div>
      {BEDS.map((bed, index) => (
        <Bed key={bed.name} index={index} bed={bed} tick={tick} />
      ))}
    </Phone>
  )
}
