import { useEffect, useRef, useState, type ReactNode } from 'react'

/// Reveals its children once they scroll into view — a gentle fade + rise. Uses
/// IntersectionObserver (works in Safari, the audience's browser; CSS
/// scroll-timeline doesn't yet). Honors prefers-reduced-motion by showing
/// immediately. One-shot: it disconnects after the first reveal.
const prefersReducedMotion = () =>
  typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

export default function Reveal({ children, y = 22, delay = 0 }: { children: ReactNode; y?: number; delay?: number }) {
  const ref = useRef<HTMLDivElement>(null)
  // Reduced-motion users start revealed (no animation) — set at init, not in the
  // effect, to avoid a synchronous setState there.
  const [shown, setShown] = useState(prefersReducedMotion)

  useEffect(() => {
    if (shown) return
    const el = ref.current
    if (!el) return
    const io = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) {
          setShown(true) // inside the observer callback — not the effect body
          io.disconnect()
        }
      },
      { threshold: 0.12, rootMargin: '0px 0px -8% 0px' },
    )
    io.observe(el)
    return () => io.disconnect()
  }, [shown])

  return (
    <div
      ref={ref}
      style={{
        opacity: shown ? 1 : 0,
        transform: shown ? 'none' : `translateY(${y}px)`,
        transition: 'opacity 0.7s ease, transform 0.7s cubic-bezier(0.22, 0.61, 0.36, 1)',
        transitionDelay: `${delay}ms`,
        willChange: shown ? 'auto' : 'opacity, transform',
      }}
    >
      {children}
    </div>
  )
}
