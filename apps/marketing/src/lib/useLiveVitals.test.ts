import { describe, expect, test } from 'bun:test'
import { nextVitals, type Vitals } from './useLiveVitals'

const start: Vitals = {
  cpu: 20,
  gpu: 10,
  mem: 12,
  temp: 60,
  fans: 3000,
  batt: 85,
  power: 12,
  down: 1,
  tick: 0,
  levels: { pulse: [], eeg: [], press: [], temp: [], resp: [], oxy: [], drip: [], tele: [] },
}

describe('nextVitals', () => {
  test('keeps every reading inside its physical range', () => {
    const extremes = [() => 0, () => 0.999]
    for (const random of extremes) {
      const vitals = Array.from({ length: 300 }).reduce<Vitals>((current) => nextVitals(current, random), start)
      expect(vitals.cpu).toBeGreaterThanOrEqual(6)
      expect(vitals.cpu).toBeLessThanOrEqual(97)
      expect(vitals.mem).toBeLessThanOrEqual(15.6)
      expect(vitals.fans).toBeGreaterThanOrEqual(1800)
      expect(vitals.fans).toBeLessThanOrEqual(6400)
    }
  })

  test('history is capped and levels stay normalised', () => {
    const vitals = Array.from({ length: 400 }).reduce<Vitals>((current) => nextVitals(current), start)
    expect(vitals.levels.pulse).toHaveLength(120)
    expect(vitals.tick).toBe(400)
    expect(vitals.levels.press.every((level) => level >= 0 && level <= 1)).toBe(true)
  })
})
