import { RELEASES_URL } from '../lib/links'
import type { LatestPrerelease } from '../lib/useLatestPrerelease'

const PURPLE = '#bf5af2'

function Dot() {
  return <span style={{ opacity: 0.4 }}>·</span>
}

/// The Dev channel's heartbeat mark — the site logo recolored purple, matching
/// the Dev app icon.
function DevHeartbeat({ size = 15 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M1 12 H6 L8 12 L9.4 5 L11 19 L12.8 9.5 L14.5 14 L16 12 H23"
        stroke={PURPLE}
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

/// A separate, opt-in section for the brave: download the newest Dev pre-release.
/// Themed purple to tie it to the Dev app's icon, and clearly fenced off from the
/// stable download above it.
export default function DevChannelSection({ prerelease }: { prerelease: LatestPrerelease | null }) {
  const dmgUrl = prerelease?.dmgUrl ?? null

  return (
    <section id="dev" style={{ padding: '0 24px 70px', display: 'flex', justifyContent: 'center' }}>
      <div
        className="px-6 py-10 md:px-10 md:py-12"
        style={{
          position: 'relative',
          width: '100%',
          maxWidth: 1080,
          textAlign: 'center',
          borderRadius: 24,
          overflow: 'hidden',
          background:
            'radial-gradient(620px 320px at 50% -20%, rgba(191,90,242,0.18), transparent 65%), linear-gradient(180deg, rgba(22,22,25,0.6), rgba(14,14,16,0.6))',
          border: '1px solid rgba(191,90,242,0.22)',
        }}
      >
        <div
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 8,
            padding: '5px 12px',
            borderRadius: 999,
            background: 'rgba(191,90,242,0.14)',
            border: '1px solid rgba(191,90,242,0.4)',
            marginBottom: 18,
          }}
        >
          <DevHeartbeat />
          <span style={{ fontSize: 12, fontWeight: 800, letterSpacing: '0.09em', color: PURPLE }}>DEV CHANNEL</span>
        </div>
        <h2
          className="text-[26px] md:text-[34px]"
          style={{ fontWeight: 680, letterSpacing: '-0.03em', margin: '0 auto 14px', lineHeight: 1.08, maxWidth: '22ch' }}
        >
          Feeling brave? Run the bleeding edge.
        </h2>
        <p style={{ fontSize: 16, lineHeight: 1.55, color: 'rgba(235,235,245,0.6)', margin: '0 auto 26px', maxWidth: '60ch' }}>
          Every branch ships a build here before it&rsquo;s released. It installs as a separate{' '}
          <strong style={{ color: '#f5f5f7', fontWeight: 600 }}>Vitals Dev</strong> app — its own purple icon and settings —
          so it sits right next to your stable copy without touching it, and auto-updates from this pre-release feed.
          Unsigned and unfinished by design.
        </p>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 12, flexWrap: 'wrap' }}>
          {dmgUrl ? (
            <a
              href={dmgUrl}
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 10,
                fontSize: 16,
                fontWeight: 600,
                color: '#fff',
                textDecoration: 'none',
                padding: '14px 24px',
                borderRadius: 14,
                background: 'linear-gradient(180deg, #c46cf5, #a23fe0)',
                boxShadow: '0 8px 26px rgba(191,90,242,0.4), inset 0 1px 0 rgba(255,255,255,0.25)',
              }}
            >
              <DevHeartbeat size={17} />
              Download Vitals Dev
            </a>
          ) : (
            <a
              href={RELEASES_URL}
              target="_blank"
              rel="noreferrer"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 9,
                fontSize: 16,
                fontWeight: 600,
                color: '#fff',
                textDecoration: 'none',
                padding: '14px 24px',
                borderRadius: 14,
                background: 'linear-gradient(180deg, #c46cf5, #a23fe0)',
                boxShadow: '0 8px 26px rgba(191,90,242,0.4), inset 0 1px 0 rgba(255,255,255,0.25)',
              }}
            >
              Browse dev builds on GitHub
            </a>
          )}
          <a
            href={RELEASES_URL}
            target="_blank"
            rel="noreferrer"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              fontSize: 16,
              fontWeight: 500,
              color: '#f5f5f7',
              textDecoration: 'none',
              padding: '14px 22px',
              borderRadius: 14,
              background: 'rgba(255,255,255,0.06)',
              border: '1px solid rgba(255,255,255,0.12)',
            }}
          >
            All pre-releases
          </a>
        </div>
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 16,
            flexWrap: 'wrap',
            marginTop: 26,
            fontSize: 12.5,
            color: 'rgba(235,235,245,0.4)',
          }}
        >
          {prerelease?.buildNumber != null && <span>Build {prerelease.buildNumber}</span>}
          {prerelease?.branch && (
            <>
              <Dot />
              <span>{prerelease.branch}</span>
            </>
          )}
          {prerelease?.sizeMB && (
            <>
              <Dot />
              <span>{prerelease.sizeMB}</span>
            </>
          )}
          <Dot />
          <span>Unsigned — right-click → Open the first launch</span>
        </div>
      </div>
    </section>
  )
}
