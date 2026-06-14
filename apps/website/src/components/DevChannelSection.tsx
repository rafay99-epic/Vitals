import { RELEASES_URL } from '../lib/links'
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
/// card. A hairline divider sets it apart, a small purple mark ties it to the
/// Dev app icon, and the copy is a quiet footnote for the curious. It blends in
/// instead of competing with the stable download above it.
export default function DevChannelSection({ prerelease }: { prerelease: LatestPrerelease | null }) {
  const dmgUrl = prerelease?.dmgUrl ?? null
  const meta = [
    prerelease?.buildNumber != null ? `Build ${prerelease.buildNumber}` : null,
    prerelease?.branch ?? null,
    prerelease?.sizeMB ?? null,
  ].filter(Boolean) as string[]

  return (
    <section id="dev" style={{ padding: '0 24px 60px', display: 'flex', justifyContent: 'center' }}>
      <div style={{ width: '100%', maxWidth: 980 }}>
        <div style={{ height: 1, background: 'rgba(255,255,255,0.07)', marginBottom: 26 }} />
        <div
          className="flex-col md:flex-row"
          style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 18 }}
        >
          <div style={{ display: 'flex', alignItems: 'flex-start', gap: 11, maxWidth: 600 }}>
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
            <div>
              <div style={{ fontSize: 14.5, fontWeight: 600, color: '#f5f5f7' }}>
                Living on the edge? Try the Dev channel.
              </div>
              <div style={{ fontSize: 13, lineHeight: 1.55, color: 'rgba(235,235,245,0.5)', marginTop: 4 }}>
                Every branch ships here first as a separate <strong style={{ color: 'rgba(235,235,245,0.72)', fontWeight: 600 }}>Vitals Dev</strong>{' '}
                app — its own purple icon and settings, won&rsquo;t touch your stable copy, auto-updates from this
                pre-release feed. Unsigned by design.
              </div>
              {meta.length > 0 && (
                <div
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 9,
                    flexWrap: 'wrap',
                    marginTop: 9,
                    fontSize: 12,
                    color: 'rgba(235,235,245,0.38)',
                  }}
                >
                  {meta.map((m, i) => (
                    <span key={m} style={{ display: 'inline-flex', alignItems: 'center', gap: 9 }}>
                      {i > 0 && <Dot />}
                      {m}
                    </span>
                  ))}
                </div>
              )}
            </div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 16, flexShrink: 0, flexWrap: 'wrap' }}>
            <a
              href={dmgUrl ?? RELEASES_URL}
              {...(dmgUrl ? {} : { target: '_blank', rel: 'noreferrer' })}
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 7,
                fontSize: 13.5,
                fontWeight: 600,
                color: PURPLE,
                textDecoration: 'none',
                padding: '8px 14px',
                borderRadius: 10,
                background: 'rgba(191,90,242,0.1)',
                border: '1px solid rgba(191,90,242,0.32)',
              }}
            >
              <DevHeartbeat size={13} />
              {dmgUrl ? 'Download Vitals Dev' : 'Browse dev builds'}
            </a>
            <a
              href={RELEASES_URL}
              target="_blank"
              rel="noreferrer"
              style={{ fontSize: 13, color: 'rgba(235,235,245,0.5)', textDecoration: 'none' }}
            >
              All pre-releases →
            </a>
          </div>
        </div>
      </div>
    </section>
  )
}
