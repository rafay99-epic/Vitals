import { Link } from '@tanstack/react-router'
import { BREW_INSTALL, BREW_INSTALL_NIGHTLY, DOWNLOAD_URL, DOWNLOAD_URL_NIGHTLY, REPO_URL } from '../../lib/links'
import { useLatestPrerelease, type LatestPrerelease } from '../../lib/useLatestPrerelease'
import { useLatestRelease, type LatestRelease } from '../../lib/useLatestRelease'
import { ButtonLink } from '../ui/Button'
import { buttonClass } from '../ui/buttonClass'
import { CommandLine } from '../ui/CommandLine'
import { Mark, NightlyMark } from '../ui/Mark'
import { Em, Meta, SectionTitle } from '../ui/text'

const stableLine = (release: LatestRelease | null) =>
  release === null ? 'Stable · updates itself' : ['Stable', release.sizeMB, 'updates itself'].filter(Boolean).join(' · ')

const nightlyDate = (publishedAt: string) => {
  const date = new Date(publishedAt)
  return Number.isNaN(date.getTime()) ? null : date.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
}

const nightlyLine = (prerelease: LatestPrerelease | null) => {
  if (prerelease === null) return 'Built every night · runs beside Stable'
  const build = prerelease.buildNumber === null ? null : `build ${prerelease.buildNumber}`
  return ['Nightly', build, nightlyDate(prerelease.publishedAt), prerelease.sizeMB, 'runs beside Stable'].filter(Boolean).join(' · ')
}

export function Admit() {
  const release = useLatestRelease()
  const prerelease = useLatestPrerelease()
  return (
    <section id="download" className="border-t border-line px-5 py-16 md:px-16 md:py-24">
      <SectionTitle still>
        Admit <Em>your Mac.</Em>
      </SectionTitle>
      <div className="mt-11 grid grid-cols-1 gap-px border-y border-line bg-line md:grid-cols-2">
        <div className="grid content-start gap-4 bg-bg py-8 md:pr-10">
          <h3 className="m-0 flex items-center gap-3.5 font-serif text-[44px] leading-none md:text-[52px]">
            <Mark className="h-8 w-12" />
            {release === null ? 'Vitals' : `Vitals ${release.version}`}
          </h3>
          <Meta>{stableLine(release)}</Meta>
          <CommandLine command={BREW_INSTALL} />
          <div className="flex flex-wrap gap-2.5">
            <ButtonLink href={DOWNLOAD_URL}>Download .dmg</ButtonLink>
            <Link to="/releases" className={buttonClass('line')}>
              Chart notes
            </Link>
          </div>
          <Meta>The .dmg is not notarized. Right click, then Open, the first time. Homebrew skips that prompt.</Meta>
        </div>
        <div id="nightly" className="grid content-start gap-4 bg-bg py-8 md:pl-10">
          <h3 className="m-0 flex items-center gap-3.5 font-serif text-[44px] leading-none md:text-[52px]">
            <NightlyMark className="h-8 w-12" />
            Nightly
          </h3>
          <Meta>{nightlyLine(prerelease)}</Meta>
          <CommandLine command={BREW_INSTALL_NIGHTLY} />
          <div className="flex flex-wrap gap-2.5">
            <ButtonLink href={prerelease?.dmgUrl ?? DOWNLOAD_URL_NIGHTLY} variant="line">
              Download Nightly
            </ButtonLink>
            <ButtonLink href={`${REPO_URL}/commits/nightly`} variant="text" external>
              What changes tonight
            </ButtonLink>
          </div>
          <Meta>Its own app, data and update feed, so it never touches Stable.</Meta>
        </div>
      </div>
      <Meta className="mt-7 block text-dim">Apple Silicon · macOS 15 or later · free and open source · phone apps pair over Tailscale</Meta>
    </section>
  )
}
