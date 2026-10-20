import { useEffect, useRef, useState } from 'react'

type CopyState = 'idle' | 'copied' | 'manual'

const LABEL: Record<CopyState, string> = { idle: 'copy', copied: 'copied', manual: 'selected, press ⌘C' }
const SPOKEN: Record<CopyState, string> = { idle: '', copied: 'Copied to clipboard', manual: 'Copy is blocked here. The command is selected, copy it with the keyboard.' }
const TONE: Record<CopyState, string> = { idle: 'text-dim hover:text-ink', copied: 'text-pulse', manual: 'text-temp' }

const selectText = (node: HTMLElement | null): boolean => {
  const selection = window.getSelection()
  if (node === null || selection === null) return false
  const range = document.createRange()
  range.selectNodeContents(node)
  selection.removeAllRanges()
  selection.addRange(range)
  return document.execCommand('copy')
}

export function CommandLine({ command, className = '' }: { command: string; className?: string }) {
  const [state, setState] = useState<CopyState>('idle')
  const code = useRef<HTMLElement>(null)
  useEffect(() => {
    if (state !== 'copied') return
    const timer = setTimeout(() => setState('idle'), 1800)
    return () => clearTimeout(timer)
  }, [state])
  const fallback = () => setState(selectText(code.current) ? 'copied' : 'manual')
  const copy = () => {
    if (navigator.clipboard === undefined) return fallback()
    navigator.clipboard.writeText(command).then(() => setState('copied'), fallback)
  }
  return (
    <div className={`flex min-w-0 items-center justify-between gap-3 border-y border-line2 py-3 font-mono text-[12px] ${className}`}>
      <code ref={code} className="min-w-0 select-all overflow-hidden text-ellipsis whitespace-nowrap">{command}</code>
      <button type="button" onClick={copy} aria-label="Copy install command" className={`shrink-0 cursor-pointer font-mono text-[11px] ${TONE[state]}`}>
        {LABEL[state]}
      </button>
      <span aria-live="polite" className="sr-only">
        {SPOKEN[state]}
      </span>
    </div>
  )
}
