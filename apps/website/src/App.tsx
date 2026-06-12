import { Analytics } from '@vercel/analytics/react'
import Nav from './components/Nav'
import Hero from './components/Hero'
import Dashboard from './components/Dashboard'
import Sensors from './components/Sensors'
import Philosophy from './components/Philosophy'
import Honesty from './components/Honesty'
import FanControl from './components/FanControl'
import Manage from './components/Manage'
import DownloadSection from './components/DownloadSection'
import Footer from './components/Footer'
import { useLiveVitals } from './lib/useLiveVitals'
import { useLatestRelease } from './lib/useLatestRelease'

export default function App() {
  const vitals = useLiveVitals()
  const release = useLatestRelease()

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
      <Nav />
      <Hero vitals={vitals} />
      <Dashboard vitals={vitals} />
      <Sensors vitals={vitals} />
      <Philosophy />
      <Honesty />
      <FanControl />
      <Manage />
      <DownloadSection release={release} />
      <Footer />
      <Analytics />
    </div>
  )
}
