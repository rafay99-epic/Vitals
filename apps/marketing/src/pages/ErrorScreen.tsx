import { StatusScreen } from './StatusScreen'
import { statusButton } from './statusStyles'
import { useTitle } from '../lib/useTitle'

/// The fallback shown when something throws — used both by the top-level
/// ErrorBoundary (render errors outside the router) and as the router's
/// errorComponent (errors inside a route). A full reload is the recovery path:
/// it rebuilds clean state, which is exactly what you want after a crash.
export default function ErrorScreen() {
  useTitle('Something went wrong — Vitals')
  return (
    <StatusScreen
      eyebrow="ERROR · NO SIGNAL"
      title="Something went wrong"
      message="This page hit an unexpected error and couldn’t finish loading. Reloading usually clears it."
      actions={
        <>
          <button type="button" onClick={() => window.location.reload()} style={statusButton.primary}>
            Reload page
          </button>
          <a href="/" style={statusButton.secondary}>
            Back to Vitals
          </a>
        </>
      }
    />
  )
}
