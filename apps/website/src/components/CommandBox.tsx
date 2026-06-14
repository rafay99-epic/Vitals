import { useState, type CSSProperties } from 'react'

/// A terminal-style command the whole box copies on click, with brief feedback.
/// Used for the primary `brew install` install path.
export default function CommandBox({ command, accent = '#1a8cff' }: { command: string; accent?: string }) {
  const [copied, setCopied] = useState(false)

  const copy = () => {
    navigator.clipboard
      ?.writeText(command)
      .then(() => {
        setCopied(true)
        setTimeout(() => setCopied(false), 1600)
      })
      .catch(() => {})
  }

  return (
    <button type="button" onClick={copy} aria-label={`Copy: ${command}`} style={box}>
      <span style={{ color: accent, fontWeight: 700, opacity: 0.9 }}>$</span>
      <code style={code}>{command}</code>
      <span style={{ ...badge, color: copied ? '#32d74b' : 'rgba(235,235,245,0.5)' }}>
        {copied ? (
          <>
            <Check /> Copied
          </>
        ) : (
          <>
            <Copy /> Copy
          </>
        )}
      </span>
    </button>
  )
}

const box: CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 9,
  width: '100%',
  maxWidth: 520,
  fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
  fontSize: 13,
  textAlign: 'left',
  color: '#f5f5f7',
  padding: '13px 15px',
  borderRadius: 13,
  cursor: 'pointer',
  background: 'rgba(0,0,0,0.35)',
  border: '1px solid rgba(255,255,255,0.14)',
}

const code: CSSProperties = {
  flex: '1 1 auto',
  minWidth: 0,
  overflow: 'hidden',
  textOverflow: 'ellipsis',
  whiteSpace: 'nowrap',
  fontFamily: 'inherit',
}

const badge: CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 5,
  flexShrink: 0,
  fontFamily: 'system-ui, sans-serif',
  fontSize: 12,
  fontWeight: 600,
}

function Copy() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
      <rect x="9" y="9" width="11" height="11" rx="2" stroke="currentColor" strokeWidth="2" />
      <path d="M5 15V5a2 2 0 0 1 2-2h10" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  )
}

function Check() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
      <path d="M5 13l4 4L19 7" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}
