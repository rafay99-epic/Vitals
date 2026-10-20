import { describe, expect, test } from 'bun:test'
import { spark } from './useLiveVitals'

// spark() turns a reading series into SVG polyline points — every chart
// on the page depends on its geometry being right.
describe('spark', () => {
  const parse = (points: string) => points.split(' ').map((p) => p.split(',').map(Number) as [number, number])

  test('emits one point per sample, spanning the full width', () => {
    const { line } = spark([1, 2, 3, 4, 5], 0, 10, 100, 40)
    const pts = parse(line)
    expect(pts).toHaveLength(5)
    expect(pts[0][0]).toBe(0)
    expect(pts[4][0]).toBe(100)
  })

  test('clamps values outside the min/max range', () => {
    const { line } = spark([-50, 500], 0, 10, 100, 40)
    for (const [, y] of parse(line)) {
      expect(y).toBeGreaterThanOrEqual(1)
      expect(y).toBeLessThanOrEqual(38)
    }
  })

  test('maps higher values to smaller y (SVG y-axis points down)', () => {
    const { line } = spark([0, 10], 0, 10, 100, 40)
    const pts = parse(line)
    expect(pts[1][1]).toBeLessThan(pts[0][1])
  })

  test('area closes the polygon along the baseline', () => {
    const { line, area } = spark([3, 7], 0, 10, 100, 40)
    expect(area.startsWith('0,40 ')).toBe(true)
    expect(area.endsWith(' 100,40')).toBe(true)
    expect(area).toContain(line)
  })
})
