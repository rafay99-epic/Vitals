import { useEffect, useRef, useState } from 'react'

const HOLD_MS = 1300

export function Hold({ label, hint }: { label: string; hint: string }) {
  const [holding, setHolding] = useState(false)
  const [sent, setSent] = useState(false)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(() => () => {
    if (timer.current !== null) clearTimeout(timer.current)
  }, [])
  const start = () => {
    setSent(false)
    setHolding(true)
    timer.current = setTimeout(() => {
      setHolding(false)
      setSent(true)
    }, HOLD_MS)
  }
  const stop = () => {
    if (timer.current !== null) clearTimeout(timer.current)
    timer.current = null
    setHolding(false)
  }
  return (
    <button
      type="button"
      data-holding={holding}
      onPointerDown={start}
      onPointerUp={stop}
      onPointerLeave={stop}
      onPointerCancel={stop}
      onKeyDown={(event) => {
        if ((event.key === ' ' || event.key === 'Enter') && !event.repeat) start()
      }}
      onKeyUp={stop}
      aria-label={`${label}, press and hold`}
      className="relative flex min-h-[92px] w-full cursor-pointer touch-none select-none items-center justify-between border-y border-line2 px-[22px] text-left"
    >
      <svg viewBox="0 0 320 92" preserveAspectRatio="none" className="pointer-events-none absolute inset-0 h-full w-full" aria-hidden="true">
        <path className="hold-trace stroke-pulse" pathLength={1} d="M0 60 H90 L104 74 L120 22 L134 60 H320" fill="none" strokeWidth="1.6" strokeLinejoin="round" />
      </svg>
      <span className={`relative font-serif text-[52px] leading-none ${sent ? 'text-pulse' : 'text-ink'}`}>{label}</span>
      <span className="relative text-right font-mono text-[10px] leading-[1.5] text-dim">
        {hint}
        {sent ? <span className="text-pulse"> · sent</span> : null}
      </span>
    </button>
  )
}
