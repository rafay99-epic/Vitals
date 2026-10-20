import { useCallback, useState, type ReactNode } from 'react'
import { Page } from '../components/layout/Page'

const slug = (title: string) =>
  title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')

interface Heading {
  id: string
  title: string
}

function useContents() {
  const [headings, setHeadings] = useState<Heading[]>([])
  const [active, setActive] = useState<string | null>(null)
  const article = useCallback((root: HTMLElement | null) => {
    if (root === null) return
    const nodes = [...root.querySelectorAll('h2[id]')]
    setHeadings(nodes.map((node) => ({ id: node.id, title: node.textContent ?? '' })))
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries.find((entry) => entry.isIntersecting)
        if (visible !== undefined) setActive(visible.target.id)
      },
      { rootMargin: '0px 0px -70% 0px' },
    )
    for (const node of nodes) observer.observe(node)
    return () => observer.disconnect()
  }, [])
  return { article, headings, active }
}

export function LegalLayout({ title, updated, children }: { title: string; updated?: string; children: ReactNode }) {
  const { article, headings, active } = useContents()
  return (
    <Page>
      <div className="grid gap-12 px-5 pb-24 pt-10 md:px-16 md:pt-16 lg:grid-cols-[260px_minmax(0,640px)] lg:gap-20">
        <nav aria-label="Contents" className="sticky top-6 hidden content-start gap-2.5 self-start font-mono text-[11.5px] lg:grid">
          {headings.map((heading) => (
            <a key={heading.id} href={`#${heading.id}`} className={`no-underline hover:text-ink ${heading.id === active ? 'text-ink' : 'text-dim'}`}>
              {heading.id === active ? <span className="mr-2 inline-block h-px w-3 bg-pulse align-middle" /> : null}
              {heading.title}
            </a>
          ))}
        </nav>
        <article ref={article} className="min-w-0">
          <h1 className="m-0 font-serif text-[48px] leading-none md:text-[72px]">{title}</h1>
          {updated === undefined ? null : <p className="mb-10 mt-3.5 font-mono text-[11px] text-dim">Last updated: {updated}</p>}
          {children}
        </article>
      </div>
    </Page>
  )
}

export function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="mb-2">
      <h2 id={slug(title)} className="mb-3.5 mt-11 font-serif text-[30px] leading-[1.1]">
        {title}
      </h2>
      {children}
    </section>
  )
}

export function P({ children }: { children: ReactNode }) {
  return <p className="mb-3 mt-0 font-sans text-[16px] leading-[1.7] text-ink2">{children}</p>
}

export function Item({ children }: { children: ReactNode }) {
  return <li className="font-sans text-[16px] leading-[1.7] text-ink2">{children}</li>
}

export function List({ children }: { children: ReactNode }) {
  return <ul className="mb-3 mt-3 grid gap-1.5 pl-[18px]">{children}</ul>
}

export function Strong({ children }: { children: ReactNode }) {
  return <span className="font-sans-medium text-ink">{children}</span>
}

export function ExtLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noreferrer" className="text-pulse underline decoration-pulse/40 underline-offset-4 hover:decoration-pulse">
      {children}
    </a>
  )
}
