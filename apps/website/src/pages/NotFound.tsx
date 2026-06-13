import { REPO_URL } from '../lib/links'
import { StatusScreen } from './StatusScreen'
import { statusButton } from './statusStyles'
import { useTitle } from '../lib/useTitle'

/// The 404 page — the router's notFoundComponent, rendered client-side for any
/// path that doesn't match a route. No fabricated content: it says plainly that
/// the page isn't here and points back to the real ones.
export default function NotFound() {
  useTitle('Page not found — Vitals')
  return (
    <StatusScreen
      eyebrow="404 · NO SIGNAL"
      title="This page isn’t here"
      message="The link may be broken, or the page may have moved. Every real reading lives back on the dashboard."
      actions={
        <>
          <a href="/" style={statusButton.primary}>
            Back to Vitals
          </a>
          <a href={REPO_URL} target="_blank" rel="noreferrer" style={statusButton.secondary}>
            View on GitHub
          </a>
        </>
      }
    />
  )
}
