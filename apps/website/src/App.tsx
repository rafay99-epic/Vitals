import Nav from './components/Nav'
import Hero from './components/Hero'
import Dashboard from './components/Dashboard'
import Sensors from './components/Sensors'
import Monitoring from './components/Monitoring'
import Glance from './components/Glance'
import Philosophy from './components/Philosophy'
import Honesty from './components/Honesty'
import FanControl from './components/FanControl'
import Manage from './components/Manage'
import DownloadSection from './components/DownloadSection'
import DevChannelSection from './components/DevChannelSection'
import Footer from './components/Footer'
import Reveal from './components/Reveal'
import { Grain } from './components/Atmosphere'
import { useLiveVitals } from './lib/useLiveVitals'
import { useLatestRelease } from './lib/useLatestRelease'
import { useLatestPrerelease } from './lib/useLatestPrerelease'
import { useTitle } from './lib/useTitle'

export default function App() {
  const vitals = useLiveVitals()
  const release = useLatestRelease()
  const prerelease = useLatestPrerelease()
  useTitle('Vitals — Your Mac has a dashboard. Apple just hid it.')

  return (
    <div
      style={{
        position: 'relative',
        minHeight: '100vh',
        width: '100%',
        overflowX: 'hidden',
        background:
          'radial-gradient(1100px 620px at 50% -8%, rgba(10,132,255,0.16), transparent 60%), radial-gradient(900px 520px at 88% 18%, rgba(255,159,10,0.10), transparent 55%), radial-gradient(800px 600px at 8% 30%, rgba(50,215,75,0.06), transparent 55%), #060608',
      }}
    >
      <div style={{ position: 'relative', zIndex: 1 }}>
        <Nav />
        <Hero vitals={vitals} />
        <Reveal>
          <Dashboard vitals={vitals} />
        </Reveal>
        <Reveal>
          <Sensors vitals={vitals} />
        </Reveal>
        <Reveal>
          <Monitoring />
        </Reveal>
        <Reveal>
          <Glance />
        </Reveal>
        <Reveal>
          <Philosophy />
        </Reveal>
        <Reveal>
          <Honesty />
        </Reveal>
        <Reveal>
          <FanControl />
        </Reveal>
        <Reveal>
          <Manage />
        </Reveal>
        {/* Download + Dev are the CTAs — always visible, never a reveal delay
            (people deep-link straight to #download). */}
        <DownloadSection release={release} />
        <DevChannelSection prerelease={prerelease} />
        <Footer />
      </div>
      <Grain />
    </div>
  )
}
