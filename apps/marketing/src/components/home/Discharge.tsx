import type { ReactNode } from 'react'
import { Reveal } from '../ui/Reveal'
import { Em, Meta, SectionTitle, Tag } from '../ui/text'

const APPS = [
  ['Xcode', '12.4 GB'],
  ['Figma', '1.1 GB · selected'],
  ['Zoom', '482 MB · selected'],
] as const

const CLEANUP = [
  { label: 'Xcode derived data', size: 6.2, color: 'bg-resp' },
  { label: 'Simulator caches', size: 4.1, color: 'bg-oxy' },
  { label: 'App caches', size: 2.9, color: 'bg-temp' },
  { label: 'Logs', size: 1.7, color: 'bg-drip' },
  { label: 'Trash', size: 0.9, color: 'bg-tele' },
] as const

const DISKS = [
  ['Macintosh HD', '1 TB · 412 GB free'],
  ['Read', '412 MB/s'],
  ['Write', '96 MB/s'],
] as const

function Column({ tag, big, unit, children, note }: { tag: string; big: string; unit?: string; children: ReactNode; note: string }) {
  return (
    <div className="rise grid content-start gap-3.5 bg-bg py-6 md:px-7">
      <Tag>{tag}</Tag>
      <span className="font-serif text-[64px] leading-none md:text-[76px]">
        {big}
        {unit === undefined ? null : <small className="ml-1 font-mono text-[11px] text-dim">{unit}</small>}
      </span>
      {children}
      <Meta>{note}</Meta>
    </div>
  )
}

function Rows({ rows }: { rows: readonly (readonly [string, string])[] }) {
  return (
    <div>
      {rows.map(([name, detail]) => (
        <div key={name} className="flex items-center justify-between border-b border-line py-2">
          <b className="font-serif text-[21px] font-normal">{name}</b>
          <span className="font-mono text-[11px] text-ink2">{detail}</span>
        </div>
      ))}
    </div>
  )
}

export function Discharge() {
  const total = CLEANUP.reduce((sum, part) => sum + part.size, 0)
  return (
    <Reveal className="border-t border-line px-5 py-16 md:px-16 md:py-24">
      <SectionTitle>
        Discharge what <Em>you don't need.</Em>
      </SectionTitle>
      <div className="mt-12 grid gap-px border-y border-line bg-line lg:grid-cols-3">
        <Column tag="Applications" big="48" note="Removes the app and every file it left behind.">
          <Rows rows={APPS} />
        </Column>
        <Column tag="Cleanup" big={total.toFixed(1)} unit="GB" note="Only regenerable data. Documents and settings are never touched.">
          <div className="flex h-3 gap-0.5" aria-hidden="true">
            {CLEANUP.map((part) => (
              <i key={part.label} className={`block h-full ${part.color}`} style={{ flexGrow: part.size }} />
            ))}
          </div>
          <ul className="m-0 grid list-none gap-1.5 p-0 font-mono text-[10.5px] text-ink2">
            {CLEANUP.map((part) => (
              <li key={part.label} className="flex items-center gap-2">
                <span className={`inline-block h-2 w-2 ${part.color}`} />
                {part.label} · {part.size} GB
              </li>
            ))}
          </ul>
        </Column>
        <Column tag="Disk health" big="98" unit="% life left" note="Wear and live throughput, read from the drive itself.">
          <Rows rows={DISKS} />
        </Column>
      </div>
    </Reveal>
  )
}
