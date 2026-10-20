import { useState } from 'react'

export function BeatSwitch({ label, initial }: { label: string; initial: boolean }) {
  const [on, setOn] = useState(initial)
  return (
    <button type="button" role="switch" aria-checked={on} aria-label={label} onClick={() => setOn((value) => !value)} className="flex h-11 w-11 shrink-0 cursor-pointer items-center justify-center">
      <svg viewBox="0 0 44 22" className="h-[22px] w-11 overflow-visible" aria-hidden="true">
        <path d="M1 14 H43" fill="none" strokeWidth="1.6" strokeLinecap="round" className={`stroke-mute transition-opacity duration-200 ${on ? 'opacity-0' : 'opacity-100'}`} />
        <path d="M1 14 H15 L19 18 L24 3 L28 14 H43" fill="none" strokeWidth="1.6" strokeLinejoin="round" strokeLinecap="round" className={`stroke-pulse transition-opacity duration-200 ${on ? 'opacity-100' : 'opacity-0'}`} />
      </svg>
    </button>
  )
}
