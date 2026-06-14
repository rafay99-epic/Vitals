/// Ambient depth behind and over the page: slow-drifting aurora blobs (behind
/// content) and a fine film-grain overlay (on top, click-through). Both are
/// purely decorative and gated on prefers-reduced-motion in CSS.

export function Aurora() {
  return (
    <div
      aria-hidden="true"
      style={{ position: 'fixed', inset: 0, zIndex: 0, pointerEvents: 'none', overflow: 'hidden' }}
    >
      <span className="vt-aurora vt-aurora-1" />
      <span className="vt-aurora vt-aurora-2" />
      <span className="vt-aurora vt-aurora-3" />
    </div>
  )
}

export function Grain() {
  return <div aria-hidden="true" className="vt-grain" style={{ position: 'fixed', inset: 0, zIndex: 3, pointerEvents: 'none' }} />
}
