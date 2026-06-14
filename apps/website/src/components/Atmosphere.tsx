/// A fine film-grain overlay on top of the page (click-through), purely
/// decorative — adds texture without the heavy glow.

export function Grain() {
  return <div aria-hidden="true" className="vt-grain" style={{ position: 'fixed', inset: 0, zIndex: 3, pointerEvents: 'none' }} />
}
