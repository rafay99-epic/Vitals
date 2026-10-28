import { Link } from '@tanstack/react-router'
import { COMPANY, DEVELOPER, DEVELOPER_URL, REPO_URL, RELEASES_URL } from '../../lib/links'

const YEAR = new Date().getFullYear()

const linkClass = 'text-dim no-underline hover:text-ink'

export function Footer() {
  return (
    <footer className="grid grid-cols-2 gap-8 border-t border-line px-5 py-12 font-mono text-[12px] leading-[1.9] text-dim md:grid-cols-[2fr_1fr_1fr_1fr] md:px-16">
      <div className="col-span-2 md:col-span-1">
        <span className="mb-2 block font-serif text-[26px] text-ink">Vitals</span>
        Take care of your Mac.
        <br />
        © {YEAR} {COMPANY} ·{' '}
        <a href={DEVELOPER_URL} target="_blank" rel="noreferrer" className={linkClass}>
          {DEVELOPER}
        </a>
        <br />
        Free software under{' '}
        <a href={`${REPO_URL}/blob/main/LICENSE`} target="_blank" rel="noreferrer" className={linkClass}>
          GPL-3.0
        </a>
        . Cleanup informed by{' '}
        <a href="https://github.com/tw93/mole" target="_blank" rel="noreferrer" className={linkClass}>
          Mole
        </a>
        .
      </div>
      <div className="flex flex-col">
        <span className="text-ink">Product</span>
        <a href="/#chart" className={linkClass}>Chart</a>
        <a href="/#sensors" className={linkClass}>Sensors</a>
        <a href="/#guard" className={linkClass}>Pressure Guard</a>
        <a href="/#remote" className={linkClass}>Remote</a>
      </div>
      <div className="flex flex-col">
        <span className="text-ink">Project</span>
        <Link to="/releases" className={linkClass}>Chart notes</Link>
        <a href="/#nightly" className={linkClass}>Nightly</a>
        <Link to="/brand" className={linkClass}>Brand</Link>
        <a href={RELEASES_URL} target="_blank" rel="noreferrer" className={linkClass}>GitHub releases</a>
        <a href={REPO_URL} target="_blank" rel="noreferrer" className={linkClass}>GitHub</a>
      </div>
      <div className="flex flex-col">
        <span className="text-ink">Legal</span>
        <Link to="/privacy" className={linkClass}>Privacy Policy</Link>
        <Link to="/terms" className={linkClass}>Terms &amp; Conditions</Link>
      </div>
    </footer>
  )
}
