export function Mark({ className = 'h-[22px] w-[34px]' }: { className?: string }) {
  return (
    <svg viewBox="0 0 48 32" className={className} aria-hidden="true">
      <path d="M2 18 H12 L16 26 L24 4 L28 18 H46" fill="none" className="stroke-pulse" strokeWidth="2.6" strokeLinejoin="round" strokeLinecap="round" />
    </svg>
  )
}

export function NightlyMark({ className = 'h-[22px] w-[34px]' }: { className?: string }) {
  return (
    <svg viewBox="0 0 48 32" className={className} aria-hidden="true">
      <path d="M1 18 H8 L10 18 L12 9 L15 25 L18 12 L21 21 L24 4 L27 18 H47" fill="none" className="stroke-eeg" strokeWidth="2.2" strokeLinejoin="round" strokeLinecap="round" />
    </svg>
  )
}
