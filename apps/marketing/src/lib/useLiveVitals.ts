import { useSyncExternalStore } from 'react'
import type { Channel } from './channels'

const HISTORY = 120
const TICK_MS = 1500

export interface Vitals {
  readonly cpu: number
  readonly gpu: number
  readonly mem: number
  readonly temp: number
  readonly fans: number
  readonly batt: number
  readonly power: number
  readonly down: number
  readonly tick: number
  readonly levels: Readonly<Record<Channel, readonly number[]>>
}

const clamp = (value: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, value))

const level = (vitals: Omit<Vitals, 'levels' | 'tick'>): Record<Channel, number> => ({
  pulse: vitals.cpu / 100,
  eeg: vitals.gpu / 100,
  press: vitals.mem / 16,
  temp: (vitals.temp - 40) / 60,
  resp: (vitals.fans - 1500) / 5000,
  oxy: vitals.batt / 100,
  drip: vitals.power / 60,
  tele: vitals.down / 10,
})

const byChannel = <T>(make: (key: Channel) => T): Record<Channel, T> => ({
  pulse: make('pulse'),
  eeg: make('eeg'),
  press: make('press'),
  temp: make('temp'),
  resp: make('resp'),
  oxy: make('oxy'),
  drip: make('drip'),
  tele: make('tele'),
})

export function nextVitals(previous: Vitals, random: () => number = Math.random): Vitals {
  const spike = random() < 0.1 ? 34 : 0
  const cpu = clamp(previous.cpu + (random() - 0.5) * 14 + spike - (previous.cpu > 60 ? 13 : 0), 6, 97)
  const gpu = clamp(previous.gpu + (random() - 0.5) * 10, 3, 88)
  const temp = clamp(previous.temp + (cpu - 35) * 0.07 + (random() - 0.5) * 2, 44, 96)
  const fans = clamp(1800 + (temp - 44) * 75 + (random() - 0.5) * 120, 1800, 6400)
  const mem = clamp(previous.mem + (random() - 0.5) * 0.35, 9.5, 15.6)
  const power = clamp(6 + cpu * 0.32 + gpu * 0.12 + (random() - 0.5) * 2, 3, 60)
  const down = clamp(previous.down + (random() - 0.5) * 0.9, 0.02, 9.6)
  const values = { cpu, gpu, mem, temp, fans, batt: previous.batt, power, down }
  const now = level(values)
  const levels = byChannel((key) => [...previous.levels[key], now[key]].slice(-HISTORY))
  return { ...values, tick: previous.tick + 1, levels }
}

const seed = (): Vitals => {
  const empty = byChannel((): readonly number[] => [])
  const start: Vitals = { cpu: 23, gpu: 18, mem: 12.8, temp: 61, fans: 3120, batt: 85, power: 14.2, down: 1.2, tick: 0, levels: empty }
  const warmed = Array.from({ length: HISTORY }).reduce<Vitals>((vitals) => nextVitals(vitals), start)
  return { ...warmed, cpu: 23, temp: 61, tick: 0 }
}

let current = seed()
const listeners = new Set<() => void>()
let timer: ReturnType<typeof setInterval> | null = null

const advance = () => {
  if (document.hidden) return
  current = nextVitals(current)
  for (const listener of listeners) listener()
}

const subscribe = (listener: () => void) => {
  listeners.add(listener)
  timer ??= setInterval(advance, TICK_MS)
  return () => {
    listeners.delete(listener)
    if (listeners.size > 0 || timer === null) return
    clearInterval(timer)
    timer = null
  }
}

const snapshot = () => current

export function useLiveVitals(): Vitals {
  return useSyncExternalStore(subscribe, snapshot, snapshot)
}
