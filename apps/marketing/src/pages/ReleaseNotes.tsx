import type { ReactNode } from 'react'

interface Line {
  id: string
  text: string
}

type Block = { kind: 'heading'; id: string; text: string } | { kind: 'list'; id: string; items: Line[] } | { kind: 'paragraph'; id: string; text: string }

const INLINE = /(\*\*([^*]+)\*\*)|(`([^`]+)`)|(\[([^\]]+)\]\((https?:\/\/[^\s)]+)\))|(https?:\/\/[^\s)]+)/g

const linkClass = 'text-pulse underline decoration-pulse/40 underline-offset-4'

function token(match: RegExpExecArray, key: string): ReactNode {
  const [, , bold, , code, , label, href, bare] = match
  if (bold !== undefined) return <strong key={key} className="font-sans-medium text-ink">{bold}</strong>
  if (code !== undefined) return <code key={key} className="font-mono text-[0.86em] text-ink">{code}</code>
  if (label !== undefined) return <a key={key} href={href} target="_blank" rel="noreferrer" className={linkClass}>{label}</a>
  return <a key={key} href={bare} target="_blank" rel="noreferrer" className={linkClass}>{(bare ?? '').replace(/^https?:\/\//, '').replace(/\/$/, '')}</a>
}

function inline(text: string, key: string): ReactNode[] {
  const nodes: ReactNode[] = []
  let last = 0
  for (const match of text.matchAll(INLINE)) {
    const index = match.index ?? 0
    if (index > last) nodes.push(text.slice(last, index))
    nodes.push(token(match, `${key}-${index}`))
    last = index + match[0].length
  }
  if (last < text.length) nodes.push(text.slice(last))
  return nodes
}

const BULLET = /^[*-]\s/
const HEADING = /^#{1,6}\s/

function blocks(body: string): Block[] {
  const result: Block[] = []
  for (const [index, raw] of body.trim().split('\n').entries()) {
    const line = raw.trim()
    const id = `line-${index}`
    const previous = result.at(-1)
    if (line === '') continue
    if (HEADING.test(line)) result.push({ kind: 'heading', id, text: line.replace(HEADING, '') })
    else if (BULLET.test(line) && previous?.kind === 'list') previous.items.push({ id, text: line.replace(BULLET, '') })
    else if (BULLET.test(line)) result.push({ kind: 'list', id, items: [{ id, text: line.replace(BULLET, '') }] })
    else result.push({ kind: 'paragraph', id, text: line })
  }
  return result
}

function BlockView({ block }: { block: Block }) {
  switch (block.kind) {
    case 'heading':
      return <h4 className="mb-2 mt-5 font-serif-italic text-[24px] font-normal leading-[1.1] first:mt-0">{inline(block.text, block.id)}</h4>
    case 'list':
      return (
        <ul className="m-0 grid list-none p-0">
          {block.items.map((item) => (
            <li key={item.id} className="border-b border-line py-2.5 font-sans text-[15px] leading-[1.5] text-ink2">
              {inline(item.text, item.id)}
            </li>
          ))}
        </ul>
      )
    case 'paragraph':
      return <p className="mb-2 mt-0 font-sans text-[15px] leading-[1.6] text-ink2">{inline(block.text, block.id)}</p>
  }
}

export function ReleaseNotes({ body }: { body: string }) {
  const parsed = blocks(body ?? '')
  if (parsed.length === 0) return <p className="m-0 font-mono text-[11px] text-dim">No notes for this release.</p>
  return (
    <div>
      {parsed.map((block) => (
        <BlockView key={block.id} block={block} />
      ))}
    </div>
  )
}
