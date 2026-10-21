import type { ReactNode } from 'react'
import { Footer } from './Footer'
import { Nav } from './Nav'

export function Page({ children, current }: { children: ReactNode; current?: 'releases' }) {
  return (
    <div className="relative min-h-screen w-full overflow-x-hidden bg-bg text-ink">
      <Nav current={current} />
      <main>{children}</main>
      <Footer />
    </div>
  )
}
