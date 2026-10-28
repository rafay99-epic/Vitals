import { Page } from '../components/layout/Page'
import { buttonClass } from '../components/ui/buttonClass'
import { Em, Meta, Tag } from '../components/ui/text'
import { useTitle } from '../lib/useTitle'

// Files under public/brand are rendered by brand/render.mjs. Re-run it after changing the artwork.
const SHOTS = [1, 2, 3, 4, 5, 6]

const KITS = [
  {
    id: 'android',
    name: 'Google Play',
    zip: '/brand/vitals-android.zip',
    size: '1080 × 1920',
    icon: { file: '/brand/android/icon-512.png', size: '512 × 512' },
    extra: { file: '/brand/android/feature-graphic.png', label: 'Feature graphic', size: '1024 × 500' },
  },
  {
    id: 'ios',
    name: 'App Store',
    zip: '/brand/vitals-ios.zip',
    size: '1320 × 2868',
    icon: { file: '/brand/ios/icon-1024.png', size: '1024 × 1024' },
    extra: null,
  },
] as const

type Kit = (typeof KITS)[number]

function Asset({ file, label, size, className }: { file: string; label: string; size: string; className: string }) {
  return (
    <a href={file} download className="group grid content-start gap-2 no-underline">
      <img src={file} alt={label} loading="lazy" className={`w-full border border-line2 transition-opacity group-hover:opacity-80 ${className}`} />
      <Meta>
        {label} · {size}
      </Meta>
    </a>
  )
}

function KitSection({ kit }: { kit: Kit }) {
  return (
    <section className="grid gap-6 border-t border-line px-5 py-10 md:px-16 md:py-14">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <h2 className="m-0 font-serif text-[44px] leading-none md:text-[56px]">{kit.name}</h2>
        <a href={kit.zip} download className={buttonClass('line')}>
          Download {kit.name} kit
        </a>
      </div>
      {/* Laid edge to edge, the six screenshots join into one heartbeat. Scrolls sideways on phones. */}
      <div className="-mx-5 overflow-x-auto px-5 md:mx-0 md:px-0">
        <div className="grid min-w-[960px] grid-cols-6">
          {SHOTS.map((n) => (
            <a key={n} href={`/brand/${kit.id}/screenshot-${n}.png`} download className="block transition-opacity hover:opacity-80">
              <img src={`/brand/${kit.id}/screenshot-${n}.png`} alt={`${kit.name} screenshot ${n}`} loading="lazy" className="block w-full" />
            </a>
          ))}
        </div>
      </div>
      <Meta>Screenshots · {kit.size} · tap one to save it</Meta>
      <div className="grid grid-cols-[1fr_2fr] gap-6 md:grid-cols-[1fr_2fr_3fr]">
        <Asset file={kit.icon.file} label="Icon" size={kit.icon.size} className="rounded-[22%]" />
        {kit.extra === null ? null : <Asset file={kit.extra.file} label={kit.extra.label} size={kit.extra.size} className="" />}
      </div>
    </section>
  )
}

/// `/brand`: store artwork for Vitals Remote, one click per kit.
export default function Brand() {
  useTitle('Brand · Vitals')
  return (
    <Page>
      <div className="grid gap-6 px-5 pb-10 pt-12 md:px-16 md:pt-[72px]">
        <Tag className="text-dim">Vitals Remote · store kit</Tag>
        <h1 className="m-0 font-serif text-[64px] leading-[0.92] md:text-[96px]">
          Your Mac has a <Em>pulse.</Em>
        </h1>
        <Meta>Every graphic is built from real captures of the app. Free to use when writing about Vitals.</Meta>
        <div className="flex flex-wrap gap-2.5">
          <a href="/brand/vitals-brand.zip" download className={buttonClass('primary')}>
            Download everything
          </a>
          {KITS.map((kit) => (
            <a key={kit.id} href={kit.zip} download className={buttonClass('line')}>
              {kit.name}
            </a>
          ))}
        </div>
        <img src="/brand/android/feature-graphic.png" alt="Vitals Remote feature graphic" className="mt-4 w-full max-w-[1024px] border border-line2" />
      </div>
      {KITS.map((kit) => (
        <KitSection key={kit.id} kit={kit} />
      ))}
    </Page>
  )
}
