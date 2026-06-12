import { LogoMark } from './icons'
import { DOWNLOAD_URL, REPO_URL } from '../lib/links'
import type { LatestRelease } from '../lib/useLatestRelease'

function Dot() {
  return <span style={{ opacity: 0.4 }}>·</span>
}

export default function DownloadSection({ release }: { release: LatestRelease | null }) {
  return (
    <section id="download" style={{ position: 'relative', padding: '70px 24px 60px', display: 'flex', justifyContent: 'center' }}>
      <div
        className="px-6 py-12 md:px-10 md:py-[70px]"
        style={{
          position: 'relative',
          width: '100%',
          maxWidth: 1080,
          textAlign: 'center',
          borderRadius: 30,
          overflow: 'hidden',
          background: 'radial-gradient(700px 360px at 50% -20%, rgba(10,132,255,0.22), transparent 65%), linear-gradient(180deg, rgba(22,22,25,0.7), rgba(14,14,16,0.7))',
          border: '1px solid rgba(255,255,255,0.1)',
        }}
      >
        <div style={{ display: 'inline-flex', marginBottom: 24 }}>
          <LogoMark box={56} radius={15} icon={34} />
        </div>
        <h2 className="text-[32px] md:text-[46px]" style={{ fontWeight: 680, letterSpacing: '-0.035em', margin: '0 auto 16px', lineHeight: 1.05, maxWidth: '16ch' }}>
          Give your Mac a dashboard.
        </h2>
        <p style={{ fontSize: 17, lineHeight: 1.5, color: 'rgba(235,235,245,0.6)', margin: '0 auto 32px', maxWidth: '46ch' }}>
          Free and open source. Ships as a signed DMG and auto-updates itself from GitHub Releases.
        </p>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 12, flexWrap: 'wrap' }}>
          <a
            href={DOWNLOAD_URL}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 10,
              fontSize: 16,
              fontWeight: 600,
              color: '#fff',
              textDecoration: 'none',
              padding: '15px 26px',
              borderRadius: 14,
              background: 'linear-gradient(180deg, #1a8cff, #0a72e8)',
              boxShadow: '0 8px 26px rgba(10,132,255,0.45), inset 0 1px 0 rgba(255,255,255,0.25)',
            }}
          >
            <svg width="17" height="17" viewBox="0 0 24 24" fill="#fff">
              <path d="M17.05 12.5c0-2.3 1.9-3.4 2-3.46-1.1-1.6-2.8-1.82-3.4-1.84-1.45-.15-2.83.85-3.56.85-.74 0-1.86-.83-3.06-.81-1.57.02-3.02.91-3.83 2.32-1.63 2.83-.42 7.02 1.17 9.32.78 1.13 1.7 2.39 2.9 2.34 1.17-.05 1.61-.75 3.02-.75 1.41 0 1.81.75 3.05.73 1.26-.02 2.06-1.14 2.83-2.27.89-1.3 1.26-2.56 1.28-2.62-.03-.01-2.45-.94-2.48-3.73zM14.7 5.31c.64-.78 1.08-1.86.96-2.94-.93.04-2.05.62-2.72 1.4-.6.69-1.12 1.79-.98 2.85 1.04.08 2.1-.53 2.74-1.31z" />
            </svg>
            Download for macOS
          </a>
          <a
            href={REPO_URL}
            target="_blank"
            rel="noreferrer"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 9,
              fontSize: 16,
              fontWeight: 500,
              color: '#f5f5f7',
              textDecoration: 'none',
              padding: '15px 24px',
              borderRadius: 14,
              background: 'rgba(255,255,255,0.06)',
              border: '1px solid rgba(255,255,255,0.12)',
            }}
          >
            <svg width="17" height="17" viewBox="0 0 24 24" fill="#f5f5f7">
              <path d="M12 2C6.48 2 2 6.58 2 12.25c0 4.53 2.87 8.37 6.84 9.73.5.1.68-.22.68-.49v-1.7c-2.78.62-3.37-1.37-3.37-1.37-.45-1.18-1.11-1.5-1.11-1.5-.91-.63.07-.62.07-.62 1 .07 1.53 1.06 1.53 1.06.89 1.56 2.34 1.11 2.91.85.09-.66.35-1.11.63-1.37-2.22-.26-4.55-1.14-4.55-5.06 0-1.12.39-2.03 1.03-2.75-.1-.26-.45-1.3.1-2.7 0 0 .84-.28 2.75 1.05A9.4 9.4 0 0112 6.84c.85 0 1.71.12 2.51.34 1.91-1.33 2.75-1.05 2.75-1.05.55 1.4.2 2.44.1 2.7.64.72 1.03 1.63 1.03 2.75 0 3.93-2.34 4.79-4.57 5.05.36.32.68.94.68 1.9v2.82c0 .27.18.6.69.49A10.26 10.26 0 0022 12.25C22 6.58 17.52 2 12 2z" />
            </svg>
            Star on GitHub
          </a>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 20, flexWrap: 'wrap', marginTop: 28, fontSize: 12.5, color: 'rgba(235,235,245,0.4)' }}>
          <span>macOS 15 or later</span>
          <Dot />
          <span>Apple Silicon</span>
          {release?.sizeMB && (
            <>
              <Dot />
              <span>{release.sizeMB}</span>
            </>
          )}
          <Dot />
          <span>{release ? `Latest ${release.version}` : 'Latest release'}</span>
        </div>
      </div>
    </section>
  )
}
