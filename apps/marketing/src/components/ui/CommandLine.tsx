import { useEffect, useState } from 'react'

export function CommandLine({ command, className = '' }: { command: string; className?: string }) {
  const [copied, setCopied] = useState(false)
  useEffect(() => {
    if (!copied) return
    const timer = setTimeout(() => setCopied(false), 1800)
    return () => clearTimeout(timer)
  }, [copied])
  const copy = () => {
    void navigator.clipboard?.writeText(command).then(() => setCopied(true), () => setCopied(false))
  }
  return (
    <div className={`flex min-w-0 items-center justify-between gap-3 border-y border-line2 py-3 font-mono text-[12px] ${className}`}>
      <code className="min-w-0 select-all overflow-hidden text-ellipsis whitespace-nowrap">{command}</code>
      <button type="button" onClick={copy} aria-label="Copy install command" className={`shrink-0 cursor-pointer font-mono text-[11px] ${copied ? 'text-pulse' : 'text-dim hover:text-ink'}`}>
        {copied ? 'copied' : 'copy'}
      </button>
      <span aria-live="polite" className="sr-only">
        {copied ? 'Copied to clipboard' : ''}
      </span>
    </div>
  )
}
