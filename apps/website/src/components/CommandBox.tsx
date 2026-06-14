import { useState, type CSSProperties } from 'react'

/// A terminal-style command with a distinct, animated copy button. The command
/// text stays selectable; the button cross-fades copy→check with a brief green
/// state and announces the result for screen readers.
export default function CommandBox({ command, accent = '#4aa3ff' }: { command: string; accent?: string }) {
  const [copied, setCopied] = useState(false)

  const copy = () => {
    navigator.clipboard
      ?.writeText(command)
      .then(() => {
        setCopied(true)
        window.setTimeout(() => setCopied(false), 1800)
      })
      .catch(() => {})
  }

  return (
    <div style={box}>
      <span aria-hidden="true" style={{ color: accent, fontWeight: 700, flexShrink: 0 }}>
        $
      </span>
      <code style={code}>{command}</code>
      <span aria-hidden="true" style={divider} />
      <button
        type="button"
        onClick={copy}
        aria-label="Copy install command"
        style={{
          ...copyBtn,
          color: copied ? '#32d74b' : 'rgba(235,235,245,0.72)',
          background: copied ? 'rgba(50,215,75,0.13)' : 'transparent',
        }}
      >
        <span aria-hidden="true" style={iconWrap}>
          <Copy className="vt-cmd-icon" style={{ opacity: copied ? 0 : 1, transform: copied ? 'scale(0.4)' : 'scale(1)' }} />
          <Check className="vt-cmd-icon" style={{ opacity: copied ? 1 : 0, transform: copied ? 'scale(1)' : 'scale(0.4)' }} />
        </span>
        <span style={{ width: 46, textAlign: 'left' }}>{copied ? 'Copied' : 'Copy'}</span>
      </button>
      <span aria-live="polite" style={srOnly}>
        {copied ? 'Copied to clipboard' : ''}
      </span>
    </div>
  )
}

const box: CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 10,
  width: '100%',
  maxWidth: 564,
  margin: '0 auto',
  fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
  fontSize: 13,
  color: '#f5f5f7',
  padding: '6px 6px 6px 15px',
  borderRadius: 13,
  background: 'linear-gradient(180deg, rgba(0,0,0,0.34), rgba(0,0,0,0.5))',
  border: '1px solid rgba(255,255,255,0.13)',
  boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.05)',
}

const code: CSSProperties = {
  flex: '1 1 auto',
  minWidth: 0,
  overflow: 'hidden',
  textOverflow: 'ellipsis',
  whiteSpace: 'nowrap',
  fontFamily: 'inherit',
  userSelect: 'all',
}

const divider: CSSProperties = {
  width: 1,
  alignSelf: 'stretch',
  margin: '6px 0',
  background: 'rgba(255,255,255,0.12)',
  flexShrink: 0,
}

const copyBtn: CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 6,
  flexShrink: 0,
  cursor: 'pointer',
  border: 'none',
  borderRadius: 9,
  padding: '8px 11px',
  fontFamily: 'system-ui, sans-serif',
  fontSize: 12.5,
  fontWeight: 600,
  transition: 'color 0.18s ease, background 0.18s ease',
}

const iconWrap: CSSProperties = {
  position: 'relative',
  display: 'inline-block',
  width: 14,
  height: 14,
  flexShrink: 0,
}

const srOnly: CSSProperties = {
  position: 'absolute',
  width: 1,
  height: 1,
  overflow: 'hidden',
  clip: 'rect(0 0 0 0)',
  whiteSpace: 'nowrap',
}

function Copy({ className, style }: { className?: string; style?: CSSProperties }) {
  return (
    <svg className={className} style={style} width="14" height="14" viewBox="0 0 24 24" fill="none">
      <rect x="9" y="9" width="11" height="11" rx="2" stroke="currentColor" strokeWidth="2" />
      <path d="M5 15V5a2 2 0 0 1 2-2h10" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  )
}

function Check({ className, style }: { className?: string; style?: CSSProperties }) {
  return (
    <svg className={className} style={style} width="14" height="14" viewBox="0 0 24 24" fill="none">
      <path d="M5 13l4 4L19 7" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}
