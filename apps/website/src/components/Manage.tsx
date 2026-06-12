const mono = "ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace"

const CHIPS = [
  'Activity Monitor-style tabs · ⌘1 ⌘2 ⌘3',
  'One window, one instance',
  'Built-in Help · ⌘?',
  'Adjustable Liquid Glass frosting',
  'Uninstall goes to the Trash — always recoverable',
  'System apps are never touched',
]

// MARK: window chrome shared by both mocks — the app's real header: traffic
// lights, brand, capsule tabs, gear.

function WindowFrame({ active, children }: { active: 'Applications' | 'Cleanup'; children: React.ReactNode }) {
  return (
    <div
      style={{
        borderRadius: 14,
        overflow: 'hidden',
        background: 'linear-gradient(180deg, rgba(16,19,24,0.96), rgba(11,13,17,0.97))',
        border: '1px solid rgba(255,255,255,0.1)',
        boxShadow: '0 40px 90px -30px rgba(0,0,0,0.8), 0 2px 10px rgba(0,0,0,0.45)',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, height: 40, padding: '0 12px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
        <div style={{ display: 'flex', gap: 6 }}>
          <span style={{ width: 10, height: 10, borderRadius: '50%', background: '#FF5F57' }} />
          <span style={{ width: 10, height: 10, borderRadius: '50%', background: '#FEBC2E' }} />
          <span style={{ width: 10, height: 10, borderRadius: '50%', background: '#28C840' }} />
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <svg width="13" height="13" viewBox="0 0 24 24">
            <polyline points="1,12 6,12 8,12 9.4,6 11,18 12.8,10 14.5,14 16,12 23,12" fill="none" stroke="#FF453A" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" />
          </svg>
          <span style={{ fontSize: 11.5, fontWeight: 600 }}>Vitals</span>
        </div>
        <div style={{ flex: 1, display: 'flex', justifyContent: 'center' }}>
          <div style={{ display: 'flex', gap: 2, padding: 2, borderRadius: 100, background: 'rgba(255,255,255,0.06)' }}>
            {(['Dashboard', 'Applications', 'Cleanup'] as const).map((tab) => (
              <span
                key={tab}
                style={{
                  fontSize: 10.5,
                  fontWeight: 500,
                  padding: '3px 9px',
                  borderRadius: 100,
                  color: tab === active ? '#f5f5f7' : 'rgba(235,235,245,0.5)',
                  background: tab === active ? 'rgba(255,255,255,0.12)' : 'transparent',
                }}
              >
                {tab}
              </span>
            ))}
          </div>
        </div>
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="rgba(235,235,245,0.55)" strokeWidth="1.6">
          <circle cx="12" cy="12" r="3.2" />
          <path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M19.1 4.9L17 7M7 17l-2.1 2.1" />
        </svg>
      </div>
      <div style={{ padding: 14 }}>{children}</div>
    </div>
  )
}

function CheckCircle({ on }: { on: boolean }) {
  return on ? (
    <svg width="15" height="15" viewBox="0 0 16 16">
      <circle cx="8" cy="8" r="8" fill="#0A84FF" />
      <path d="M4.6 8.2l2.2 2.2 4.4-4.6" fill="none" stroke="#fff" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  ) : (
    <span style={{ width: 15, height: 15, borderRadius: '50%', border: '1.5px solid rgba(255,255,255,0.22)', display: 'inline-block' }} />
  )
}

function AppTile({ letter, from, to }: { letter: string; from: string; to: string }) {
  return (
    <span
      style={{
        width: 22,
        height: 22,
        borderRadius: 6,
        background: `linear-gradient(160deg, ${from}, ${to})`,
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: 11,
        fontWeight: 700,
        color: '#fff',
      }}
    >
      {letter}
    </span>
  )
}

// MARK: Applications mock

const MOCK_APPS = [
  { letter: 'A', from: '#FF9F4A', to: '#E0494B', name: 'Acorn', id: 'com.flyingmeat.Acorn', version: '8.2', size: '64.1 MB', selected: true, running: false },
  { letter: 'B', from: '#2AB0FF', to: '#0A5FCC', name: 'Beacon', id: 'app.beacon.desktop', version: '2.4.1', size: '418 MB', selected: true, running: false },
  { letter: 'C', from: '#34D85F', to: '#0E8A4A', name: 'Cosmos', id: 'io.cosmos.mac', version: '5.0', size: '1.36 GB', selected: false, running: true },
  { letter: 'D', from: '#BF5AF2', to: '#7A2FB8', name: 'Drafts', id: 'com.agiletortoise.Drafts', version: '46.1', size: '188 MB', selected: false, running: false },
  { letter: 'E', from: '#00D8F0', to: '#0072A8', name: 'Ember', id: 'com.realmacsoftware.Ember', version: '1.9', size: '92.4 MB', selected: false, running: false },
]

function ApplicationsMock() {
  return (
    <WindowFrame active="Applications">
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
        <div>
          <div style={{ fontSize: 18, fontWeight: 700, letterSpacing: '-0.02em' }}>48 applications</div>
          <div style={{ fontSize: 10.5, color: 'rgba(235,235,245,0.5)' }}>372 GB on disk · 11 running</div>
        </div>
        <div style={{ flex: 1 }} />
        <div style={{ display: 'flex', alignItems: 'center', gap: 5, padding: '4px 9px', borderRadius: 100, background: 'rgba(255,255,255,0.06)' }}>
          <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="rgba(235,235,245,0.5)" strokeWidth="2.4" strokeLinecap="round">
            <circle cx="10" cy="10" r="6.5" />
            <path d="M15 15l5 5" />
          </svg>
          <span style={{ fontSize: 10, color: 'rgba(235,235,245,0.45)' }}>Search</span>
        </div>
        <div style={{ display: 'flex', padding: 2, borderRadius: 100, background: 'rgba(255,255,255,0.06)', fontSize: 10 }}>
          <span style={{ padding: '2px 8px', borderRadius: 100, background: 'rgba(255,255,255,0.12)' }}>Name</span>
          <span style={{ padding: '2px 8px', color: 'rgba(235,235,245,0.5)' }}>Size</span>
        </div>
      </div>

      <div style={{ borderRadius: 10, background: 'rgba(255,255,255,0.045)', border: '1px solid rgba(255,255,255,0.08)', overflow: 'hidden' }}>
        {MOCK_APPS.map((app, index) => (
          <div
            key={app.name}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 9,
              padding: '8px 11px',
              borderTop: index > 0 ? '1px solid rgba(255,255,255,0.05)' : 'none',
              background: app.selected ? 'rgba(10,132,255,0.10)' : 'transparent',
            }}
          >
            <CheckCircle on={app.selected} />
            <AppTile letter={app.letter} from={app.from} to={app.to} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ fontSize: 11.5, fontWeight: 500 }}>{app.name}</span>
                {app.running && (
                  <span style={{ fontSize: 8.5, fontWeight: 600, color: '#34D85F', background: 'rgba(52,216,95,0.16)', padding: '1px 5px', borderRadius: 100 }}>
                    Running
                  </span>
                )}
              </div>
              <div style={{ fontSize: 9.5, color: 'rgba(235,235,245,0.38)' }}>{app.id}</div>
            </div>
            <span style={{ fontSize: 9.5, color: 'rgba(235,235,245,0.38)' }}>{app.version}</span>
            <span style={{ fontSize: 10.5, fontFamily: mono, color: 'rgba(235,235,245,0.6)', width: 52, textAlign: 'right' }}>{app.size}</span>
          </div>
        ))}
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 12 }}>
        <span style={{ width: 11, height: 11, borderRadius: 3, border: '1.5px solid rgba(255,255,255,0.25)' }} />
        <span style={{ fontSize: 10.5, color: 'rgba(235,235,245,0.55)' }}>Select all</span>
        <span style={{ fontSize: 10.5, color: 'rgba(235,235,245,0.55)' }}>2 selected · 482 MB</span>
        <div style={{ flex: 1 }} />
        <span
          style={{
            fontSize: 11,
            fontWeight: 600,
            color: '#fff',
            padding: '6px 13px',
            borderRadius: 8,
            background: 'linear-gradient(180deg, #ff5147, #d93a30)',
            boxShadow: '0 2px 8px rgba(224,73,75,0.4), inset 0 1px 0 rgba(255,255,255,0.2)',
          }}
        >
          Uninstall…
        </span>
      </div>
    </WindowFrame>
  )
}

// MARK: Cleanup mock

const MOCK_CATEGORIES = [
  { letter: 'X', tint: '#2AB0FF', title: 'Xcode derived data', detail: 'Build products Xcode recreates on the next build', size: '1.21 GB', items: '1 item', selected: true },
  { letter: 'D', tint: '#FF9F4A', title: 'Developer caches', detail: 'npm, bun, pip, cargo, Gradle, Go package caches', size: '9.03 GB', items: '6 items', selected: true },
  { letter: 'H', tint: '#FFD60A', title: 'Homebrew cache', detail: 'Downloaded bottles and old formula versions', size: '147 MB', items: '1 item', selected: false },
  { letter: 'A', tint: '#BF5AF2', title: 'App caches', detail: 'Per-app caches — Apple system caches are kept', size: '5.11 GB', items: '92 items', selected: true },
]

function CleanupMock() {
  return (
    <WindowFrame active="Cleanup">
      <div style={{ display: 'flex', alignItems: 'center', marginBottom: 12 }}>
        <div>
          <div style={{ fontSize: 19, fontWeight: 700, letterSpacing: '-0.02em' }}>15.79 GB</div>
          <div style={{ fontSize: 10.5, color: 'rgba(235,235,245,0.5)' }}>reclaimable across 5 categories — all of it regenerable</div>
        </div>
        <div style={{ flex: 1 }} />
        <span style={{ fontSize: 10.5, padding: '5px 11px', borderRadius: 8, border: '1px solid rgba(255,255,255,0.12)', color: 'rgba(235,235,245,0.7)' }}>
          Rescan
        </span>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
        {MOCK_CATEGORIES.map((category) => (
          <div
            key={category.title}
            style={{
              borderRadius: 10,
              padding: 10,
              background: category.selected ? 'rgba(10,132,255,0.10)' : 'rgba(255,255,255,0.045)',
              border: category.selected ? '1px solid rgba(10,132,255,0.5)' : '1px solid rgba(255,255,255,0.08)',
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 6 }}>
              <span
                style={{
                  width: 20,
                  height: 20,
                  borderRadius: 6,
                  background: `${category.tint}24`,
                  color: category.tint,
                  display: 'inline-flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 10,
                  fontWeight: 700,
                }}
              >
                {category.letter}
              </span>
              <span style={{ fontSize: 11, fontWeight: 600, flex: 1 }}>{category.title}</span>
              <CheckCircle on={category.selected} />
            </div>
            <div style={{ fontSize: 9.5, color: 'rgba(235,235,245,0.45)', lineHeight: 1.35, marginBottom: 8, minHeight: 25 }}>{category.detail}</div>
            <div style={{ display: 'flex', alignItems: 'baseline' }}>
              <span style={{ fontSize: 13, fontWeight: 700, fontFamily: mono }}>{category.size}</span>
              <div style={{ flex: 1 }} />
              <span style={{ fontSize: 9, color: 'rgba(235,235,245,0.35)' }}>{category.items}</span>
            </div>
          </div>
        ))}
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 12 }}>
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#34D85F" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M12 2l8 4v5c0 5-3.5 8.5-8 11-4.5-2.5-8-6-8-11V6z" />
        </svg>
        <span style={{ fontSize: 9.5, color: 'rgba(235,235,245,0.45)' }}>Only regenerable data — documents and settings are never touched.</span>
        <div style={{ flex: 1 }} />
        <span
          style={{
            fontSize: 11,
            fontWeight: 600,
            color: '#fff',
            padding: '6px 13px',
            borderRadius: 8,
            background: 'linear-gradient(180deg, #1a8cff, #0a72e8)',
            boxShadow: '0 2px 8px rgba(10,132,255,0.4), inset 0 1px 0 rgba(255,255,255,0.2)',
          }}
        >
          Clean 15.4 GB
        </span>
      </div>
    </WindowFrame>
  )
}

// MARK: Section

/// The new app-management features, recreated as live components in the
/// app's exact design language — same approach as the hero dropdown and
/// dashboard mocks.
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
        <div className="grid grid-cols-1 lg:grid-cols-[0.8fr_1.2fr] gap-8 lg:gap-12" style={{ alignItems: 'center', marginBottom: 56 }}>
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
          <ApplicationsMock />
        </div>

        {/* Cleanup */}
        <div className="grid grid-cols-1 lg:grid-cols-[1.2fr_0.8fr] gap-8 lg:gap-12" style={{ alignItems: 'center', marginBottom: 56 }}>
          <div className="order-last lg:order-first">
            <CleanupMock />
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

        {/* Polish chips */}
        <div style={{ textAlign: 'center' }}>
          <div style={{ fontSize: 13, fontWeight: 600, letterSpacing: '0.04em', color: '#00D8F0', marginBottom: 14 }}>AND THE POLISH</div>
          <h3 className="text-[26px] md:text-[32px]" style={{ fontWeight: 660, letterSpacing: '-0.03em', margin: '0 0 20px', lineHeight: 1.12 }}>
            One design, every surface.
          </h3>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, justifyContent: 'center', maxWidth: 760, margin: '0 auto' }}>
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
      </div>
    </section>
  )
}
