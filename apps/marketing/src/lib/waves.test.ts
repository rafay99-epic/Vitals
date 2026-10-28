import { describe, expect, test } from 'bun:test'
import { flatPath, wavePath, type Wave } from './waves'

const WAVES: Wave[] = ['ecg', 'art', 'wave', 'pleth', 'eeg', 'step', 'bars']

const xs = (d: string) => [...d.matchAll(/[MLHVQCS]\s?(-?\d+(?:\.\d+)?)/g)].map((match) => Number(match[1]))

describe('wavePath', () => {
  test('every wave starts at the left edge and stays inside the box', () => {
    for (const wave of WAVES) {
      const d = wavePath(wave, [0.2, 0.9, 0.4, 1, 0], 300, 60, 3)
      expect(d.startsWith('M')).toBe(true)
      const numbers = [...d.matchAll(/-?\d+(?:\.\d+)?/g)].map((match) => Number(match[0]))
      expect(numbers.every((value) => value >= -60 && value <= 360)).toBe(true)
    }
  })

  test('clamps levels outside 0..1 so spikes cannot leave the trace', () => {
    expect(wavePath('step', [5, -3], 100, 40)).toBe(wavePath('step', [1, 0], 100, 40))
  })

  test('a taller level draws a taller beat', () => {
    const peak = (d: string) => Math.min(...[...d.matchAll(/L[\d.]+ ([\d.]+)/g)].map((match) => Number(match[1])))
    expect(peak(wavePath('ecg', [1], 100, 60))).toBeLessThan(peak(wavePath('ecg', [0.1], 100, 60)))
  })

  test('the eeg wave is the same for the same seed', () => {
    expect(wavePath('eeg', [0.5, 0.5], 100, 40, 7)).toBe(wavePath('eeg', [0.5, 0.5], 100, 40, 7))
  })

  test('no levels and flat lines both draw a level baseline', () => {
    expect(wavePath('ecg', [], 200, 100)).toBe(flatPath(200, 100))
    expect(xs(flatPath(200, 100)).at(-1)).toBe(200)
  })
})
