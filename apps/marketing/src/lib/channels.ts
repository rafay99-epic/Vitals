import type { Wave } from './waves'

export type Channel = 'pulse' | 'eeg' | 'press' | 'temp' | 'resp' | 'oxy' | 'drip' | 'tele'

export interface ChannelSpec {
  readonly tag: string
  readonly label: string
  readonly stroke: string
  readonly text: string
  readonly wave: Wave
}

export const channels: Record<Channel, ChannelSpec> = {
  pulse: { tag: 'PULSE', label: 'CPU', stroke: '#5cf2a6', text: 'text-pulse', wave: 'ecg' },
  eeg: { tag: 'EEG', label: 'GPU', stroke: '#f2ec6b', text: 'text-eeg', wave: 'eeg' },
  press: { tag: 'PRESS', label: 'Memory', stroke: '#ff6b8b', text: 'text-press', wave: 'art' },
  temp: { tag: 'TEMP', label: 'Thermal', stroke: '#ffb45c', text: 'text-temp', wave: 'wave' },
  resp: { tag: 'RESP', label: 'Fans', stroke: '#74d4ff', text: 'text-resp', wave: 'wave' },
  oxy: { tag: 'OXY', label: 'Battery', stroke: '#c8a8ff', text: 'text-oxy', wave: 'pleth' },
  drip: { tag: 'DRIP', label: 'Power', stroke: '#6f9bff', text: 'text-drip', wave: 'step' },
  tele: { tag: 'TELE', label: 'Network', stroke: '#b9c4d0', text: 'text-tele', wave: 'bars' },
}

export const MUTE = '#5c5c5c'

export const ALARM_HIGH = '#ff4d6d'
