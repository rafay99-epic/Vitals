import { REPO_URL } from '../lib/links'
import { StatusScreen } from './StatusScreen'
import { statusButton } from './statusStyles'

/// The 404 page. Built to `dist/404.html`, which Vercel serves with a 404
/// status for any path that doesn't match a real file. No fabricated content —
/// it says plainly that the page isn't here and points back to the real ones.
export default function NotFound() {
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
