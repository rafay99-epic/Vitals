import { Page } from './components/layout/Page'
import { Admit } from './components/home/Admit'
import { Alarms } from './components/home/Alarms'
import { Breathing } from './components/home/Breathing'
import { ChartLanes } from './components/home/ChartLanes'
import { Discharge } from './components/home/Discharge'
import { Hero } from './components/home/Hero'
import { Private } from './components/home/Private'
import { Rounds } from './components/home/Rounds'
import { Sensors } from './components/home/Sensors'
import { useTitle } from './lib/useTitle'

export default function App() {
  useTitle('Vitals · The bedside chart for your Mac')
  return (
    <Page>
      <Hero />
      <ChartLanes />
      <Sensors />
      <Breathing />
      <Discharge />
      <Alarms />
      <Rounds />
      <Private />
      <Admit />
    </Page>
  )
}
