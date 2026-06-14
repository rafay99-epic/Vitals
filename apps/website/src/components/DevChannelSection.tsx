import CommandBox from './CommandBox'
import { BREW_INSTALL_DEV, RELEASES_URL } from '../lib/links'
import type { LatestPrerelease } from '../lib/useLatestPrerelease'

const PURPLE = '#bf5af2'

function Dot() {
  return <span style={{ opacity: 0.35 }}>·</span>
}

/// The Dev channel's heartbeat mark — the site logo recolored purple, matching
/// the Dev app icon.
function DevHeartbeat({ size = 14 }: { size?: number }) {
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

/// A deliberately understated aside under the main download — not a second hero
/// card. A hairline divider sets it apart and a small purple mark ties it to the
/// Dev app icon. Leads with the Homebrew command (same as Stable), with the .dmg
/// as a quiet fallback. It blends in instead of competing with the download above.
export default function DevChannelSection({ prerelease }: { prerelease: LatestPrerelease | null }) {
  const dmgUrl = prerelease?.dmgUrl ?? null
  const meta = [
    prerelease?.buildNumber != null ? `Build ${prerelease.buildNumber}` : null,
    prerelease?.branch ?? null,
    prerelease?.sizeMB ?? null,
  ].filter(Boolean) as string[]

  return (
    <section id="dev" style={{ padding: '0 24px 60px', display: 'flex', justifyContent: 'center' }}>
      <div style={{ width: '100%', maxWidth: 760 }}>
        <div style={{ height: 1, background: 'rgba(255,255,255,0.07)', marginBottom: 26 }} />
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
          <span
            style={{
              flexShrink: 0,
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: 26,
              height: 26,
              borderRadius: 8,
              background: 'rgba(191,90,242,0.13)',
              border: '1px solid rgba(191,90,242,0.3)',
              marginTop: 1,
            }}
          >
            <DevHeartbeat />
          </span>
          <div style={{ minWidth: 0, flex: '1 1 auto' }}>
            <div style={{ fontSize: 14.5, fontWeight: 600, color: '#f5f5f7' }}>
              Living on the edge? Try the Dev channel.
            </div>
            <div style={{ fontSize: 13, lineHeight: 1.55, color: 'rgba(235,235,245,0.5)', marginTop: 4 }}>
              Every branch ships here first as a separate <strong style={{ color: 'rgba(235,235,245,0.72)', fontWeight: 600 }}>Vitals Dev</strong>{' '}
              app — its own purple icon and settings, won&rsquo;t touch your stable copy, auto-updates from this
              pre-release feed. Unsigned by design.
            </div>

            <div style={{ marginTop: 14 }}>
              <CommandBox command={BREW_INSTALL_DEV} accent={PURPLE} />
            </div>

            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 10,
                flexWrap: 'wrap',
                marginTop: 12,
                fontSize: 12.5,
                color: 'rgba(235,235,245,0.4)',
              }}
            >
              <a
                href={dmgUrl ?? RELEASES_URL}
                {...(dmgUrl ? {} : { target: '_blank', rel: 'noreferrer' })}
                style={{ color: 'rgba(235,235,245,0.62)', textDecoration: 'none' }}
              >
                {dmgUrl ? 'Download .dmg' : 'Browse dev builds'}
              </a>
              <Dot />
              <a href={RELEASES_URL} target="_blank" rel="noreferrer" style={{ color: 'rgba(235,235,245,0.62)', textDecoration: 'none' }}>
                All pre-releases →
              </a>
              {meta.map((m) => (
                <span key={m} style={{ display: 'inline-flex', alignItems: 'center', gap: 10 }}>
                  <Dot />
                  {m}
                </span>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
