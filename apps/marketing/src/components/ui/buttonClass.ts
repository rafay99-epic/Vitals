export type ButtonVariant = 'primary' | 'line' | 'text' | 'nightly'

const VARIANT: Record<ButtonVariant, string> = {
  primary: 'bg-ink px-4 text-bg hover:bg-ink2',
  line: 'border border-line3 px-4 text-ink hover:bg-raise',
  text: 'px-1 text-ink underline decoration-mute underline-offset-4 hover:decoration-ink',
  nightly: 'bg-eeg px-4 text-bg hover:opacity-90',
}

const BASE = 'inline-flex min-h-11 items-center justify-center gap-2 whitespace-nowrap font-sans-medium text-[14px] no-underline transition-colors'

export const buttonClass = (variant: ButtonVariant, block = false) => `${BASE} ${VARIANT[variant]} ${block ? 'w-full' : ''}`
