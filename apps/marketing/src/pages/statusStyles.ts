import type { CSSProperties } from 'react'

/// Button styles for the standalone status pages (404, error boundary), kept in
/// a plain module so the component files only export components. They mirror the
/// landing page's primary/secondary CTAs.
const primary: CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 9,
  fontSize: 15,
  fontWeight: 590,
  color: '#fff',
  textDecoration: 'none',
  padding: '12px 22px',
  borderRadius: 13,
  border: 'none',
  cursor: 'pointer',
  background: 'linear-gradient(180deg, #1a8cff, #0a72e8)',
  boxShadow: '0 6px 22px rgba(10,132,255,0.42), inset 0 1px 0 rgba(255,255,255,0.25)',
}

const secondary: CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 8,
  fontSize: 15,
  fontWeight: 500,
  color: '#f5f5f7',
  textDecoration: 'none',
  padding: '12px 20px',
  borderRadius: 13,
  border: '1px solid rgba(255,255,255,0.12)',
  cursor: 'pointer',
  background: 'rgba(255,255,255,0.06)',
}

export const statusButton = { primary, secondary }
