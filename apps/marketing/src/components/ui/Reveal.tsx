import { useEffect, useRef, useState, type ReactNode } from 'react'

const reduced = () => typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches

export function useSeen<T extends Element>() {
  const ref = useRef<T>(null)
  const [seen, setSeen] = useState(reduced)
  useEffect(() => {
    const node = ref.current
    if (seen || node === null) return
    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return
        setSeen(true)
        observer.disconnect()
      },
      { threshold: 0.12, rootMargin: '0px 0px -8% 0px' },
    )
    observer.observe(node)
    return () => observer.disconnect()
  }, [seen])
  return [ref, seen] as const
}

export function Reveal({ children, className = '', id }: { children: ReactNode; className?: string; id?: string }) {
  const [ref, seen] = useSeen<HTMLElement>()
  return (
    <section ref={ref} id={id} className={`${seen ? 'is-shown' : ''} ${className}`}>
      {children}
    </section>
  )
}
