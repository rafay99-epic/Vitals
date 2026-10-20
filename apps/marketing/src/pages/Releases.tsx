import { useState, type ReactNode } from 'react'
import { Page } from '../components/layout/Page'
import { buttonClass } from '../components/ui/buttonClass'
import { Meta } from '../components/ui/text'
import { RELEASES_URL } from '../lib/links'
import { useReleases, type ReleaseSummary } from '../lib/useReleases'
import { useTitle } from '../lib/useTitle'
import { ReleaseNotes } from './ReleaseNotes'

type Filter = 'all' | 'stable' | 'nightly'

const FILTERS: { value: Filter; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'stable', label: 'Stable' },
  { value: 'nightly', label: 'Nightly' },
]

const MATCH: Record<Filter, (release: ReleaseSummary) => boolean> = {
  all: () => true,
  stable: (release) => !release.prerelease,
  nightly: (release) => release.prerelease,
}

const channelTone = (release: ReleaseSummary, latest: boolean) => {
  if (release.prerelease) return 'text-eeg'
  return latest ? 'text-pulse' : 'text-dim'
}

const formatDate = (epochMs: number) =>
  epochMs > 0 ? new Date(epochMs).toLocaleString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : null

function Filters({ value, onChange }: { value: Filter; onChange: (value: Filter) => void }) {
  return (
    <div role="group" aria-label="Channel" className="flex gap-5 border-b border-line">
      {FILTERS.map((filter) => (
        <button
          key={filter.value}
          type="button"
          aria-pressed={filter.value === value}
          onClick={() => onChange(filter.value)}
          className={`-mb-px min-h-11 cursor-pointer border-b-[1.5px] font-mono-medium text-[11px] uppercase tracking-[0.08em] ${filter.value === value ? 'border-ink text-ink' : 'border-transparent text-dim hover:text-ink'}`}
        >
          {filter.label}
        </button>
      ))}
    </div>
  )
}

function Entry({ release, latest }: { release: ReleaseSummary; latest: boolean }) {
  const channel = release.prerelease ? 'NIGHTLY' : 'STABLE'
  const tone = channelTone(release, latest)
  const meta = [formatDate(release.publishedAt), release.sizeMB].filter(Boolean).join(' · ')
  return (
    <article className="grid gap-6 border-t border-line px-5 py-8 md:grid-cols-[280px_1fr] md:gap-10 md:px-16 md:py-[34px]">
      <div className="grid content-start gap-2">
        <b className="break-words font-serif text-[40px] font-normal leading-none md:text-[48px]">{release.name}</b>
        {meta === '' ? null : <Meta>{meta}</Meta>}
        <span className={`font-mono-medium text-[10px] tracking-[0.1em] ${tone}`}>{latest ? `${channel} · LATEST` : channel}</span>
        <div className="mt-2 flex flex-wrap gap-2.5">
          {release.dmgUrl === null ? null : (
            <a href={release.dmgUrl} className={buttonClass(release.prerelease ? 'line' : 'primary')}>
              Download
            </a>
          )}
          <a href={release.url} target="_blank" rel="noreferrer" className={buttonClass('text')}>
            On GitHub
          </a>
        </div>
      </div>
      <ReleaseNotes body={release.body} />
    </article>
  )
}

function Status({ title, detail, children }: { title: string; detail: string; children?: ReactNode }) {
  return (
    <div className="grid gap-3 border-t border-line px-5 py-12 md:px-16" role="status">
      <div className="h-px bg-line3" />
      <b className="font-serif-italic text-[30px] font-normal leading-none">{title}</b>
      <Meta>{detail}</Meta>
      {children}
    </div>
  )
}

export default function Releases() {
  useTitle('Chart notes · Vitals releases')
  const { status, releases, hasMore, loadingMore, loadMore, retry } = useReleases()
  const [filter, setFilter] = useState<Filter>('all')
  const shown = releases.filter(MATCH[filter])
  const newest = releases.find((release) => !release.prerelease)?.tag
  return (
    <Page current="releases">
      <div className="flex flex-col gap-6 px-5 pb-7 pt-12 md:flex-row md:items-end md:justify-between md:px-16 md:pt-[72px]">
        <div className="grid gap-2">
          <h1 className="m-0 font-serif text-[64px] leading-[0.92] md:text-[96px]">Chart notes.</h1>
          <Meta>Releases, newest first. Stable updates itself. Nightly is built every night.</Meta>
        </div>
        <Filters value={filter} onChange={setFilter} />
      </div>
      {status === 'loading' ? <Status title="Reading the chart." detail="Fetching the release list from GitHub." /> : null}
      {status === 'error' ? (
        <Status title="Could not read the notes." detail="The release list did not load. GitHub may be rate limiting us for a moment.">
          <div className="flex flex-wrap gap-2.5">
            <button type="button" onClick={retry} className={`${buttonClass('primary')} cursor-pointer border-0`}>
              Try again
            </button>
            <a href={RELEASES_URL} target="_blank" rel="noreferrer" className={buttonClass('line')}>
              Releases on GitHub
            </a>
          </div>
        </Status>
      ) : null}
      {status === 'ready' && shown.length === 0 ? <Status title="Nothing here yet." detail="No published releases on this channel." /> : null}
      {status === 'ready' ? shown.map((release) => <Entry key={release.tag} release={release} latest={release.tag === newest} />) : null}
      {status === 'ready' && hasMore ? (
        <div className="flex justify-center border-t border-line py-8">
          <button type="button" onClick={loadMore} disabled={loadingMore} className={`${buttonClass('line')} cursor-pointer bg-transparent disabled:opacity-40`}>
            {loadingMore ? 'Loading' : 'Load older notes'}
          </button>
        </div>
      ) : null}
    </Page>
  )
}
