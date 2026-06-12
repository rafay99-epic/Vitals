import { useEffect, useState } from 'react'

const REPO = 'rafay99-epic/Vitals'
const RELEASES = `https://github.com/${REPO}/releases`
const DOWNLOAD = `${RELEASES}/latest/download/Vitals.dmg`

const FEATURES = [
  {
    icon: '🌡️',
    title: 'Die-level temperatures',
    body: 'Every CPU, GPU, SSD, and battery sensor Apple Silicon exposes, mapped onto a live die view — not just one average number.',
  },
  {
    icon: '🌀',
    title: 'Real fan control',
    body: 'Set exact fan speeds or hand control back to macOS, from the app or the menu bar. One password to set up, none after that.',
  },
  {
    icon: '📊',
    title: 'CPU usage & top processes',
    body: 'Overall utilisation plus the processes responsible for it, sampled the same way Activity Monitor does.',
  },
  {
    icon: '🧠',
    title: 'Memory, properly',
    body: 'App, wired, compressed, cached, swap, and the kernel’s own memory-pressure signal — the full Activity Monitor picture.',
  },
  {
    icon: '🔔',
    title: 'Overheat alerts',
    body: 'A notification when the CPU stays hot or macOS starts throttling, with cooldowns so it never nags.',
  },
  {
    icon: '📈',
    title: 'History that survives restarts',
    body: 'Charts for the last half hour in the app, and an optional CSV log on disk for studying long-term trends.',
  },
]

function useLatestVersion(): string | null {
  const [version, setVersion] = useState<string | null>(null)
  useEffect(() => {
    fetch(`https://api.github.com/repos/${REPO}/releases/latest`)
      .then((response) => (response.ok ? response.json() : null))
      .then((release) => {
        if (release?.tag_name) setVersion(release.tag_name)
      })
      .catch(() => {})
  }, [])
  return version
}

export default function App() {
  const version = useLatestVersion()

  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100 antialiased">
      <header className="mx-auto flex max-w-5xl items-center justify-between px-6 py-5">
        <span className="text-lg font-semibold tracking-tight">
          <span className="mr-2">⚡️</span>Vitals
        </span>
        <nav className="flex items-center gap-6 text-sm text-zinc-400">
          <a href="#features" className="transition hover:text-zinc-100">
            Features
          </a>
          <a href={RELEASES} className="transition hover:text-zinc-100">
            Releases
          </a>
          <a href={`https://github.com/${REPO}`} className="transition hover:text-zinc-100">
            GitHub
          </a>
        </nav>
      </header>

      <main>
        <section className="mx-auto max-w-3xl px-6 pt-20 pb-16 text-center">
          <p className="mb-4 inline-block rounded-full border border-zinc-800 bg-zinc-900 px-3 py-1 text-xs text-zinc-400">
            Free & open source · Apple Silicon
          </p>
          <h1 className="text-5xl font-semibold tracking-tight text-balance sm:text-6xl">
            Your Mac’s vitals,
            <span className="bg-gradient-to-r from-orange-400 to-rose-500 bg-clip-text text-transparent">
              {' '}
              at a glance
            </span>
          </h1>
          <p className="mx-auto mt-6 max-w-xl text-lg text-zinc-400">
            Temperatures, fans, CPU, and memory for M-series Macs — in a dashboard and your menu
            bar, with real fan control when you want to take over.
          </p>
          <div className="mt-10 flex flex-col items-center justify-center gap-4 sm:flex-row">
            <a
              href={DOWNLOAD}
              className="rounded-xl bg-zinc-100 px-6 py-3 font-medium text-zinc-950 transition hover:bg-white"
            >
              Download for macOS
            </a>
            <a
              href={RELEASES}
              className="rounded-xl border border-zinc-800 px-6 py-3 font-medium text-zinc-300 transition hover:border-zinc-600"
            >
              All releases
            </a>
          </div>
          <p className="mt-4 text-sm text-zinc-500">
            {version ? `Latest ${version} · ` : ''}Requires an Apple Silicon Mac on macOS 15+
          </p>
        </section>

        <section id="features" className="mx-auto max-w-5xl px-6 pb-24">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {FEATURES.map((feature) => (
              <article
                key={feature.title}
                className="rounded-2xl border border-zinc-800/80 bg-zinc-900/50 p-6 transition hover:border-zinc-700"
              >
                <div className="mb-3 text-2xl">{feature.icon}</div>
                <h2 className="mb-2 font-medium">{feature.title}</h2>
                <p className="text-sm leading-relaxed text-zinc-400">{feature.body}</p>
              </article>
            ))}
          </div>
        </section>
      </main>

      <footer className="border-t border-zinc-900">
        <div className="mx-auto flex max-w-5xl flex-col items-center justify-between gap-2 px-6 py-8 text-sm text-zinc-500 sm:flex-row">
          <span>
            Vitals · open source at{' '}
            <a
              href={`https://github.com/${REPO}`}
              className="underline-offset-4 transition hover:text-zinc-300 hover:underline"
            >
              {REPO}
            </a>
          </span>
          <span>Made for Apple Silicon Macs</span>
        </div>
      </footer>
    </div>
  )
}
