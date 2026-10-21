import type { ReactNode } from 'react'

import { buttonClass, type ButtonVariant } from './buttonClass'

export function ButtonLink({ href, variant = 'primary', block = false, external = false, children }: { href: string; variant?: ButtonVariant; block?: boolean; external?: boolean; children: ReactNode }) {
  return (
    <a href={href} className={buttonClass(variant, block)} {...(external ? { target: '_blank', rel: 'noreferrer' } : {})}>
      {children}
    </a>
  )
}
