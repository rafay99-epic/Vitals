export type Wave = 'ecg' | 'art' | 'wave' | 'pleth' | 'eeg' | 'step' | 'bars'

const n = (value: number) => value.toFixed(1)

const noise = (index: number) => {
  const x = Math.sin(index * 12.9898 + 78.233) * 43758.5453
  return x - Math.floor(x) - 0.5
}

type Draw = (levels: number[], w: number, h: number, seed: number) => string

const ecg: Draw = (levels, w, h) => {
  const bw = w / levels.length
  const base = h * 0.66
  return levels.reduce((d, level, i) => {
    const x = i * bw
    const amp = h * 0.12 + h * 0.5 * level
    return `${d} L${n(x + bw * 0.3)} ${n(base)} Q${n(x + bw * 0.36)} ${n(base - h * 0.08)} ${n(x + bw * 0.42)} ${n(base)} L${n(x + bw * 0.5)} ${n(base + h * 0.08)} L${n(x + bw * 0.56)} ${n(base - amp)} L${n(x + bw * 0.62)} ${n(base + h * 0.16)} L${n(x + bw * 0.68)} ${n(base)} Q${n(x + bw * 0.8)} ${n(base - h * 0.14)} ${n(x + bw * 0.92)} ${n(base)} L${n(x + bw)} ${n(base)}`
  }, `M0 ${n(base)}`)
}

const art: Draw = (levels, w, h) => {
  const bw = w / levels.length
  const base = h * 0.82
  return levels.reduce((d, level, i) => {
    const x = i * bw
    const amp = h * 0.25 + h * 0.5 * level
    return `${d} L${n(x + bw * 0.12)} ${n(base)} C${n(x + bw * 0.2)} ${n(base - amp)} ${n(x + bw * 0.26)} ${n(base - amp)} ${n(x + bw * 0.34)} ${n(base - amp * 0.72)} L${n(x + bw * 0.42)} ${n(base - amp * 0.6)} Q${n(x + bw * 0.48)} ${n(base - amp * 0.68)} ${n(x + bw * 0.54)} ${n(base - amp * 0.5)} Q${n(x + bw * 0.8)} ${n(base - amp * 0.08)} ${n(x + bw)} ${n(base)}`
  }, `M0 ${n(base)}`)
}

const sine: Draw = (levels, w, h) => {
  const cw = w / levels.length
  const mid = h * 0.55
  return levels.reduce((d, level, i) => {
    const x = i * cw
    const amp = h * 0.42 * Math.max(0.08, level)
    return `${d} C${n(x + cw * 0.25)} ${n(mid - amp)} ${n(x + cw * 0.45)} ${n(mid - amp)} ${n(x + cw * 0.6)} ${n(mid)} S${n(x + cw * 0.9)} ${n(mid + amp * 0.35)} ${n(x + cw)} ${n(mid)}`
  }, `M0 ${n(mid)}`)
}

const pleth: Draw = (levels, w, h) => {
  const cw = w / levels.length
  const base = h * 0.85
  return levels.reduce((d, level, i) => {
    const x = i * cw
    const amp = h * 0.2 + h * 0.5 * level
    return `${d} C${n(x + cw * 0.15)} ${n(base)} ${n(x + cw * 0.2)} ${n(base - amp)} ${n(x + cw * 0.35)} ${n(base - amp)} C${n(x + cw * 0.55)} ${n(base - amp)} ${n(x + cw * 0.7)} ${n(base - amp * 0.2)} ${n(x + cw)} ${n(base)}`
  }, `M0 ${n(base)}`)
}

const eeg: Draw = (levels, w, h, seed) => {
  const steps = levels.length * 6
  const sw = w / steps
  const mid = h * 0.55
  const points = Array.from({ length: steps }, (_, index) => {
    const i = index + 1
    const level = levels[Math.min(levels.length - 1, Math.floor(i / 6))] ?? 0
    return `L${n(i * sw)} ${n(mid + noise(i + seed) * 2 * h * 0.45 * Math.max(0.1, level))}`
  })
  return `M0 ${n(mid)} ${points.join(' ')}`
}

const step: Draw = (levels, w, h) => {
  const sw = w / levels.length
  return levels
    .map((level, i) => {
      const y = n(h * 0.9 - h * 0.75 * level)
      return `${i === 0 ? 'M0' : `L${n(i * sw)}`} ${y} L${n((i + 1) * sw)} ${y}`
    })
    .join(' ')
}

const bars: Draw = (levels, w, h) => {
  const sw = w / levels.length
  const base = h * 0.92
  return levels.map((level, i) => `M${n(i * sw + sw / 2)} ${n(base)} V${n(base - Math.max(2, h * 0.8 * level))}`).join(' ')
}

const DRAW: Record<Wave, Draw> = { ecg, art, wave: sine, pleth, eeg, step, bars }

export function wavePath(wave: Wave, levels: number[], width: number, height: number, seed = 0): string {
  if (levels.length === 0) return `M0 ${n(height * 0.66)} H${width}`
  return DRAW[wave](levels.map((level) => Math.min(1, Math.max(0, level))), width, height, seed)
}

export function flatPath(width: number, height: number): string {
  return `M0 ${n(height * 0.66)} H${width}`
}
