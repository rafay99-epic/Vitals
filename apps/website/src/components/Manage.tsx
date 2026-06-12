const CHIPS = [
  'Activity Monitor-style tabs · ⌘1 ⌘2 ⌘3',
  'One window, one instance',
  'Built-in Help · ⌘?',
  'Adjustable Liquid Glass frosting',
  'Uninstall goes to the Trash — always recoverable',
  'System apps are never touched',
]

function Screenshot({ src, alt }: { src: string; alt: string }) {
  return (
    <div
      style={{
        borderRadius: 14,
        overflow: 'hidden',
        border: '1px solid rgba(255,255,255,0.10)',
        boxShadow: '0 40px 90px -30px rgba(0,0,0,0.8), 0 2px 10px rgba(0,0,0,0.45)',
        lineHeight: 0,
      }}
    >
      <img src={src} alt={alt} loading="lazy" style={{ width: '100%', height: 'auto', display: 'block' }} />
    </div>
  )
}

/// The new app-management features, shown with real screenshots of the app.
export default function Manage() {
  return (
    <section id="manage" style={{ position: 'relative', padding: '80px 24px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      <div style={{ width: '100%', maxWidth: 1080 }}>
        <div style={{ textAlign: 'center', marginBottom: 44 }}>
          <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#BF5AF2', marginBottom: 14 }}>BEYOND MONITORING</div>
          <h2 className="text-[32px] md:text-[44px]" style={{ fontWeight: 670, letterSpacing: '-0.035em', margin: '0 auto 16px', lineHeight: 1.06, maxWidth: '18ch' }}>
            It cleans up after your apps, too.
          </h2>
          <p style={{ fontSize: 16, lineHeight: 1.5, color: 'rgba(235,235,245,0.55)', margin: '0 auto', maxWidth: '56ch' }}>
            The same window that watches your temperatures now uninstalls apps completely and reclaims the disk space macOS quietly eats — with the
            same careful philosophy underneath.
          </p>
        </div>

        {/* Applications */}
        <div className="grid grid-cols-1 lg:grid-cols-[0.85fr_1.15fr] gap-8 lg:gap-12" style={{ alignItems: 'center', marginBottom: 56 }}>
          <div>
            <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#BF5AF2', marginBottom: 12 }}>APPLICATIONS</div>
            <h3 className="text-[26px] md:text-[32px]" style={{ fontWeight: 660, letterSpacing: '-0.03em', margin: '0 0 14px', lineHeight: 1.12 }}>
              Uninstall, completely.
            </h3>
            <p style={{ fontSize: 15.5, lineHeight: 1.55, color: 'rgba(235,235,245,0.6)', margin: '0 0 12px' }}>
              Select any app and Vitals finds what it left behind — caches, preferences, containers, launch agents — shows you every file first, and
              moves it all to the Trash.
            </p>
            <p style={{ fontSize: 15.5, lineHeight: 1.55, color: 'rgba(235,235,245,0.6)', margin: 0 }}>
              Nothing is deleted permanently, running apps are handled gracefully, and system software is never even listed.
            </p>
          </div>
          <Screenshot src="/screenshots/applications.jpg" alt="The Applications tab listing installed apps with sizes and multi-select" />
        </div>

        {/* Cleanup */}
        <div className="grid grid-cols-1 lg:grid-cols-[1.15fr_0.85fr] gap-8 lg:gap-12" style={{ alignItems: 'center', marginBottom: 56 }}>
          <div className="order-last lg:order-first">
            <Screenshot src="/screenshots/cleanup.jpg" alt="The Cleanup tab showing reclaimable space across categories" />
          </div>
          <div>
            <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#FF9F4A', marginBottom: 12 }}>CLEANUP</div>
            <h3 className="text-[26px] md:text-[32px]" style={{ fontWeight: 660, letterSpacing: '-0.03em', margin: '0 0 14px', lineHeight: 1.12 }}>
              Reclaim gigabytes of regenerable data.
            </h3>
            <p style={{ fontSize: 15.5, lineHeight: 1.55, color: 'rgba(235,235,245,0.6)', margin: '0 0 12px' }}>
              Xcode derived data, npm and Homebrew caches, app caches, old logs — scanned, sized, and cleaned with one click.
            </p>
            <p style={{ fontSize: 15.5, lineHeight: 1.55, color: 'rgba(235,235,245,0.6)', margin: 0 }}>
              Only data your apps rebuild automatically. Documents and settings are never on the menu.
            </p>
          </div>
        </div>

        {/* Polish chips + menu bar shot */}
        <div className="grid grid-cols-1 lg:grid-cols-[1fr_300px] gap-8 lg:gap-12" style={{ alignItems: 'center' }}>
          <div>
            <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#00D8F0', marginBottom: 14 }}>AND THE POLISH</div>
            <h3 className="text-[26px] md:text-[32px]" style={{ fontWeight: 660, letterSpacing: '-0.03em', margin: '0 0 18px', lineHeight: 1.12 }}>
              One design, every surface.
            </h3>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {CHIPS.map((chip) => (
                <span
                  key={chip}
                  style={{
                    fontSize: 13,
                    color: 'rgba(235,235,245,0.72)',
                    padding: '7px 13px',
                    borderRadius: 100,
                    background: 'rgba(255,255,255,0.05)',
                    border: '1px solid rgba(255,255,255,0.1)',
                  }}
                >
                  {chip}
                </span>
              ))}
            </div>
          </div>
          <Screenshot src="/screenshots/menubar.jpg" alt="The menu bar panel with live sparklines and fan presets" />
        </div>
      </div>
    </section>
  )
}
