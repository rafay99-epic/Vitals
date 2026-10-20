import type { ReactNode } from 'react'

export function Tag({ children, className = 'text-ink2' }: { children: ReactNode; className?: string }) {
  return <span className={`font-mono-medium text-tag uppercase tracking-[0.1em] ${className}`}>{children}</span>
}

export function Meta({ children, className = 'text-dim' }: { children: ReactNode; className?: string }) {
  return <span className={`font-mono text-meta ${className}`}>{children}</span>
}

export function DemoNote({ className = '' }: { className?: string }) {
  return <Tag className={`block text-dim ${className}`}>Demo readings, not your Mac</Tag>
}

export function Em({ children, className = 'text-pulse' }: { children: ReactNode; className?: string }) {
  return <em className={`font-serif-italic not-italic ${className}`}>{children}</em>
}

export function SectionTitle({ children, className = '', still = false }: { children: ReactNode; className?: string; still?: boolean }) {
  return <h2 className={`${still ? '' : 'rise'} m-0 font-serif text-[44px] leading-[0.98] tracking-[-0.01em] md:text-[64px] ${className}`}>{children}</h2>
}

export function Lede({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <p className={`max-w-[520px] font-sans text-[15px] leading-[1.6] text-ink2 ${className}`}>{children}</p>
}
