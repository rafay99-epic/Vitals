import { useEffect, useState } from 'react'

// Faithful port of the design prototype's data simulation: same seeds, same
// 1.6 s tick, same clamps, so the page demos "every number is real" motion.
const TEMP0 = [45, 44, 45, 46, 45, 44, 45, 47, 46, 45, 44, 45, 46, 45, 46, 45, 44, 45, 46, 47, 46, 45, 45, 45]
const CPU0 = [12, 14, 11, 18, 22, 15, 12, 20, 28, 18, 14, 12, 16, 22, 40, 30, 18, 14, 22, 55, 80, 45, 28, 21]
const MEM0 = [12.2, 12.3, 12.3, 12.4, 12.4, 12.3, 12.4, 12.5, 12.4, 12.4, 12.3, 12.4, 12.5, 12.4, 12.4, 12.5, 12.4, 12.4, 12.5, 12.4, 12.4, 12.4, 12.4, 12.4]

export function spark(arr: number[], min: number, max: number, w: number, h: number) {
  const n = arr.length
  const pts = arr
    .map((v, i) => {
      const x = n <= 1 ? 0 : (i / (n - 1)) * w
      let t = (v - min) / (max - min)
      t = Math.max(0, Math.min(1, t))
      const y = h - t * (h - 3) - 2
      return x.toFixed(1) + ',' + y.toFixed(1)
    })
    .join(' ')
  return { line: pts, area: '0,' + h + ' ' + pts + ' ' + w + ',' + h }
}

export function useLiveVitals() {
  const [state, setState] = useState({ temp: TEMP0, cpu: CPU0, mem: MEM0, tick: 0 })

  useEffect(() => {
    const timer = setInterval(() => {
      setState((s) => {
        let nt = Math.round(s.temp[s.temp.length - 1] + (Math.random() * 4 - 2))
        nt = Math.max(40, Math.min(52, nt))
        let nc = Math.round(s.cpu[s.cpu.length - 1] + (Math.random() * 34 - 17))
        nc = Math.max(5, Math.min(100, nc))
        let nm = +(s.mem[s.mem.length - 1] + (Math.random() * 0.4 - 0.2)).toFixed(1)
        nm = Math.max(11.6, Math.min(13.4, nm))
        return {
          temp: [...s.temp.slice(-23), nt],
          cpu: [...s.cpu.slice(-23), nc],
          mem: [...s.mem.slice(-23), nm],
          tick: s.tick + 1,
        }
      })
    }, 1600)
    return () => clearInterval(timer)
  }, [])

  const { temp, cpu, mem, tick } = state
  const tempVal = temp[temp.length - 1]
  const cpuPct = cpu[cpu.length - 1]
  const memVal = mem[mem.length - 1]
  const avgCpu = Math.max(38, tempVal - 3)
  const ts = spark(temp, 38, 54, 100, 40)
  const cs = spark(cpu, 0, 100, 100, 40)
  const ms = spark(mem, 9, 16, 100, 40)
  const fan = tempVal > 49 ? 1200 + (tempVal - 49) * 190 : 0

  return {
    avgCpu,
    tempVal,
    cpuPct: cpuPct + '%',
    memVal: memVal.toFixed(1) + 'G',
    tempLine: ts.line,
    tempArea: ts.area,
    cpuLine: cs.line,
    cpuPctArea: cs.area,
    memLine: ms.line,
    memArea: ms.area,
    chartCpu: spark(temp, 0, 64, 1000, 200).line,
    chartHot: spark(temp.map((v) => v + 3), 0, 64, 1000, 200).line,
    chartGpu: spark(temp.map((v) => v - 4), 0, 64, 1000, 200).line,
    cpuTemp: tempVal,
    fanLabel: fan === 0 ? 'Idle' : Math.round(fan / 10) * 10 + ' rpm',
    gpuLoad: 8 + (tick % 6) * 3 + '%',
    power: (8 + (tempVal - 42) * 0.45).toFixed(1) + ' W',
  }
}

export type LiveVitals = ReturnType<typeof useLiveVitals>
