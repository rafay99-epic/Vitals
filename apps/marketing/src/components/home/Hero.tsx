import { BREW_INSTALL, DOWNLOAD_URL } from '../../lib/links'
import { useLiveVitals } from '../../lib/useLiveVitals'
import { ButtonLink } from '../ui/Button'
import { CommandLine } from '../ui/CommandLine'
import { Em, Meta, Tag } from '../ui/text'
import { Trace } from '../ui/Trace'

function VitalStrip() {
  const vitals = useLiveVitals()
  const cells = [
    { key: 'pulse', label: 'Pulse · CPU', value: Math.round(vitals.cpu), unit: '%', className: 'text-pulse' },
    { key: 'press', label: 'Press · Memory', value: vitals.mem.toFixed(1), unit: '/16 GB', className: 'text-press' },
    { key: 'temp', label: 'Temp · Thermal', value: `${Math.round(vitals.temp)}°`, unit: '', className: 'text-temp' },
    { key: 'resp', label: 'Resp · Fans', value: Math.round(vitals.fans), unit: 'rpm', className: 'text-resp' },
    { key: 'oxy', label: 'Oxy · Battery', value: vitals.batt, unit: '%', className: 'text-oxy' },
  ]
  return (
    <div className="mt-14 grid grid-cols-2 gap-px border-y border-line bg-line md:grid-cols-5" aria-label="Demo readings">
      {cells.map((cell) => (
        <div key={cell.key} className="grid gap-1.5 bg-bg px-5 pb-5 pt-4 last:col-span-2 md:first:pl-16 md:last:col-span-1">
          <Tag className={cell.className}>{cell.label}</Tag>
          <b className={`font-serif text-[44px] font-normal leading-none md:text-[56px] ${cell.className}`}>
            {cell.value}
            {cell.unit === '' ? null : <small className="ml-1 font-mono text-[11px]">{cell.unit}</small>}
          </b>
        </div>
      ))}
    </div>
  )
}

export function Hero() {
  return (
    <section className="relative overflow-hidden pt-2">
      <Trace channel="pulse" beats={4} width={390} height={130} className="h-[130px] w-full md:hidden" />
      <Trace channel="pulse" beats={13} width={1296} height={270} className="hidden h-[270px] w-full md:block" />
      <div className="grid grid-cols-1 gap-8 px-5 md:grid-cols-[1fr_372px] md:items-end md:gap-12 md:px-16">
        <h1 className="m-0 font-serif text-[62px] leading-[0.9] tracking-[-0.015em] md:text-[104px] md:leading-[0.86] lg:text-[132px]">
          The bedside chart for <Em>your Mac.</Em>
        </h1>
        <div className="grid gap-[18px]">
          <p className="m-0 font-sans text-[15px] leading-[1.6] text-ink2">
            Pulse, pressure, heat and breath, read straight from the silicon. Check it from bed, put it to rest with one hold.
          </p>
          <div className="flex flex-wrap gap-2.5">
            <ButtonLink href={DOWNLOAD_URL}>Download for macOS</ButtonLink>
            <ButtonLink href="#remote" variant="line">
              iPhone · Android · Web
            </ButtonLink>
          </div>
          <CommandLine command={BREW_INSTALL} />
          <Meta>Free · Open source · Apple Silicon · macOS 15 or later</Meta>
        </div>
      </div>
      <VitalStrip />
    </section>
  )
}
