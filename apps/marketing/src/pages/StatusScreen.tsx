import type { ReactNode } from 'react'
import { Mark } from '../components/ui/Mark'
import { wavePath } from '../lib/waves'

export interface StatusScreenProps {
  beats: number[]
  stroke: string
  title: ReactNode
  message?: string
  code: string[]
  actions: ReactNode
}

const flatTail = (beats: number[], total: number) => {
  const width = 1296
  const beatWidth = width / total
  const live = wavePath('ecg', beats, beatWidth * beats.length, 200)
  return `${live} L${width} ${(200 * 0.66).toFixed(1)}`
}

function PlainNav() {
  return (
    <header className="flex items-center gap-7 px-5 py-5 md:px-16 md:py-[22px]">
      <a href="/" className="mr-auto flex items-center gap-2.5 font-serif text-[26px] text-ink no-underline">
        <Mark />
        Vitals
      </a>
      <nav aria-label="Primary" className="flex items-center gap-6 font-sans text-[13px]">
        <a href="/#chart" className="hidden text-ink2 no-underline hover:text-ink sm:inline">
          Chart
        </a>
        <a href="/releases" className="text-ink2 no-underline hover:text-ink">
          Releases
        </a>
        <a href="/#download" className="bg-ink px-3.5 py-2.5 font-sans-medium text-bg no-underline hover:bg-ink2">
          Download
        </a>
      </nav>
    </header>
  )
}

export function StatusScreen({ beats, stroke, title, message, code, actions }: StatusScreenProps) {
  return (
    <div className="flex min-h-screen w-full flex-col overflow-x-hidden bg-bg text-ink">
      <PlainNav />
      <main className="relative flex flex-1 flex-col justify-end gap-10 px-5 pb-16 md:px-16">
        <svg viewBox="0 0 1296 200" preserveAspectRatio="none" className="trace-draw is-drawn absolute inset-x-0 top-10 h-[140px] w-full md:h-[200px]" aria-hidden="true">
          <path d={flatTail(beats, 12)} pathLength={1} fill="none" stroke={stroke} strokeWidth={1.8} strokeLinejoin="round" />
        </svg>
        <div className="mt-[220px] grid gap-[18px] md:mt-[300px]">
          <h1 className="m-0 max-w-[820px] font-serif text-[52px] leading-[0.92] md:text-[84px]">{title}</h1>
          {message === undefined ? null : <p className="m-0 max-w-[520px] font-sans text-[15px] leading-[1.6] text-ink2">{message}</p>}
          <div className="flex flex-wrap gap-2.5">{actions}</div>
        </div>
        <div className="font-mono text-[11px] leading-[1.8] text-dim md:absolute md:bottom-16 md:right-16 md:text-right">
          {code.map((line) => (
            <span key={line} className="block">
              {line}
            </span>
          ))}
        </div>
      </main>
    </div>
  )
}
