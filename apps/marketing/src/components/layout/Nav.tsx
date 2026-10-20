import { Link } from '@tanstack/react-router'
import { useEffect, useRef, useState } from 'react'
import { Mark } from '../ui/Mark'

const LINKS = [
  { href: '/#chart', label: 'Chart' },
  { href: '/#sensors', label: 'Sensors' },
  { href: '/#guard', label: 'Guard' },
  { href: '/#remote', label: 'Remote' },
] as const

function MenuSheet({ onClose }: { onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    dialog.current?.showModal()
  }, [])
  const close = () => dialog.current?.close()
  return (
    <dialog ref={dialog} onClose={onClose} aria-label="Menu" className="m-0 h-dvh max-h-none w-full max-w-none flex-col bg-bg px-5 py-5 text-ink backdrop:bg-bg open:flex">
      <div className="flex items-center justify-between">
        <Link to="/" onClick={close} className="flex items-center gap-2.5 font-serif text-[26px] text-ink no-underline">
          <Mark />
          Vitals
        </Link>
        <button type="button" onClick={close} className="min-h-11 cursor-pointer font-mono text-[11px] text-ink2">
          Close
        </button>
      </div>
      <nav className="mt-10 flex flex-col">
        {LINKS.map((link) => (
          <a key={link.href} href={link.href} onClick={close} className="border-t border-line py-4 font-serif text-[40px] leading-none text-ink no-underline">
            {link.label}
          </a>
        ))}
        <Link to="/releases" onClick={close} className="border-y border-line py-4 font-serif text-[40px] leading-none text-ink no-underline">
          Chart notes
        </Link>
      </nav>
      <a href="/#download" onClick={close} className="mt-auto inline-flex min-h-12 items-center justify-center bg-ink font-sans-medium text-[15px] text-bg no-underline">
        Download
      </a>
    </dialog>
  )
}

export function Nav({ current }: { current?: 'releases' }) {
  const [open, setOpen] = useState(false)
  return (
    <header className="relative z-20 flex items-center gap-7 px-5 py-5 md:px-16 md:py-[22px]">
      <Link to="/" className="mr-auto flex items-center gap-2.5 font-serif text-[26px] text-ink no-underline">
        <Mark />
        Vitals
      </Link>
      <nav aria-label="Primary" className="hidden items-center gap-7 font-sans text-[13px] md:flex">
        {LINKS.map((link) => (
          <a key={link.href} href={link.href} className="text-ink2 no-underline hover:text-ink">
            {link.label}
          </a>
        ))}
        <Link to="/releases" className={`no-underline hover:text-ink ${current === 'releases' ? 'text-ink' : 'text-ink2'}`}>
          Releases
        </Link>
        <a href="/#download" className="bg-ink px-3.5 py-2.5 font-sans-medium text-bg no-underline hover:bg-ink2">
          Download
        </a>
      </nav>
      <button type="button" onClick={() => setOpen(true)} aria-expanded={open} className="min-h-11 cursor-pointer font-mono text-[11px] text-ink2 md:hidden">
        Menu
      </button>
      {open ? <MenuSheet onClose={() => setOpen(false)} /> : null}
    </header>
  )
}
