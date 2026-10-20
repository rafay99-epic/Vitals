import { useState } from 'react'
import { useLiveVitals } from '../../lib/useLiveVitals'
import { Reveal } from '../ui/Reveal'
import { Lede, Meta, SectionTitle, Tag } from '../ui/text'
import { Trace } from '../ui/Trace'

const WINDOW = 60

const linePath = (values: readonly number[]) =>
  values.map((value, i) => `${i === 0 ? 'M' : 'L'}${((i / Math.max(values.length - 1, 1)) * 560).toFixed(1)} ${(100 - value * 90).toFixed(1)}`).join(' ')

function Scrubber() {
  const vitals = useLiveVitals()
  const history = vitals.levels.resp.slice(-WINDOW)
  const [back, setBack] = useState(0)
  const index = Math.max(0, history.length - 1 - back)
  const rpm = Math.round(1500 + (history[index] ?? 0) * 5000)
  const marker = history.length <= 1 ? 560 : (index / (history.length - 1)) * 560
  return (
    <div className="rise grid gap-3.5">
      <svg viewBox="0 0 560 110" preserveAspectRatio="none" className="block h-[110px] w-full" aria-hidden="true">
        <path d={linePath(history)} fill="none" className="stroke-resp" strokeWidth={1.6} strokeLinejoin="round" />
        <path d={`M${marker.toFixed(1)} 0 V110`} stroke="#fff" strokeWidth={1} />
      </svg>
      <div className="flex items-baseline justify-between">
        <Tag className="text-resp">{back === 0 ? 'Fan speed · now' : `Fan speed · ${back} readings ago`}</Tag>
        <b className="font-serif text-[72px] font-normal leading-none text-resp md:text-[104px]">{rpm}</b>
      </div>
      <input
        className="hairline w-full cursor-pointer"
        type="range"
        min={0}
        max={WINDOW - 1}
        value={WINDOW - 1 - back}
        onChange={(event) => setBack(WINDOW - 1 - Number(event.target.value))}
        aria-label="Scrub back through the last 60 fan readings"
      />
      <div className="flex justify-between font-mono text-[10.5px] text-dim">
        <span>60 readings ago</span>
        <span>drag to read the past</span>
        <span>now</span>
      </div>
    </div>
  )
}

export function Breathing() {
  return (
    <Reveal className="border-t border-line px-5 py-16 md:px-16 md:py-24">
      <div className="grid items-center gap-12 md:grid-cols-2 md:gap-16">
        <div className="rise grid content-start gap-5">
          <SectionTitle>Breathing.</SectionTitle>
          <Lede>Every fan, live, with its minimum and maximum. Scrub back through the timeline to see when your Mac started working hard.</Lede>
          <Trace channel="resp" beats={10} width={560} height={40} className="h-10 w-full" />
        </div>
        <Scrubber />
      </div>
      <div className="mt-16 grid gap-px border-y border-line bg-line md:grid-cols-2">
        <div className="rise grid gap-2 bg-bg py-6 md:pr-7">
          <Tag className="text-dim">Other tools · fanless Mac</Tag>
          <b className="font-serif text-[54px] font-normal leading-none text-mute line-through decoration-2">1,850 rpm</b>
          <Meta>A number with no fan behind it.</Meta>
        </div>
        <div className="rise grid gap-2 bg-bg py-6 md:pl-7">
          <Tag className="text-resp">Vitals · fanless Mac</Tag>
          <b className="font-serif text-[54px] font-normal leading-none">Fanless.</b>
          <Meta>No fan, no number. Idle fans read idle.</Meta>
        </div>
      </div>
    </Reveal>
  )
}
