import type { ReactNode } from 'react'
import { useLiveVitals } from '../../lib/useLiveVitals'
import { Reveal } from '../ui/Reveal'
import { DemoNote, Em, SectionTitle, Tag } from '../ui/text'

function Cell({ tag, tone, value, unit, children }: { tag: string; tone: string; value: ReactNode; unit: string; children: ReactNode }) {
  return (
    <div className="rise grid content-start gap-3 bg-bg py-6 pr-6 md:px-7 md:py-7">
      <Tag className={tone}>{tag}</Tag>
      <b className={`font-serif text-[48px] font-normal leading-none md:text-[58px] ${tone}`}>
        {value}
        <small className="ml-1 font-mono text-[11px] text-ink2">{unit}</small>
      </b>
      <p className="m-0 max-w-[300px] font-sans text-[13.5px] leading-[1.55] text-ink2">{children}</p>
    </div>
  )
}

export function Sensors() {
  const vitals = useLiveVitals()
  return (
    <Reveal id="sensors" className="border-t border-line px-5 py-16 md:px-16 md:py-24">
      <SectionTitle>
        Straight from <Em>the silicon.</Em>
      </SectionTitle>
      <DemoNote className="mt-4" />
      <div className="mt-12 grid grid-cols-1 gap-px border-y border-line bg-line sm:grid-cols-2 lg:grid-cols-3">
        <Cell tag="Temp · Chip temperature" tone="text-temp" value={`${Math.round(vitals.temp)}°`} unit="C die">
          Vitals reads per cluster die sensors, not a guess from power draw.
        </Cell>
        <Cell tag="Resp · Fan speed" tone="text-resp" value={Math.round(vitals.fans)} unit="rpm">
          Vitals reads RPM from the SMC. When the fan stops, it says so.
        </Cell>
        <Cell tag="Oxy · Battery health" tone="text-oxy" value="96" unit="% · 212 cycles">
          Capacity, cycle count, charge state and condition in one place.
        </Cell>
        <Cell tag="Pulse · CPU and GPU" tone="text-pulse" value={Math.round(vitals.cpu)} unit={`% CPU · ${Math.round(vitals.gpu)}% GPU`}>
          Per core load and GPU activity, charted over time.
        </Cell>
        <Cell tag="Drip · Power" tone="text-drip" value={vitals.power.toFixed(1)} unit="W package">
          See what a workload costs while it runs.
        </Cell>
        <Cell tag="Tele · Network" tone="text-tele" value={vitals.down.toFixed(1)} unit="MB/s down">
          Throughput on the active interface, with Wi-Fi signal when you are on the air.
        </Cell>
      </div>
    </Reveal>
  )
}
