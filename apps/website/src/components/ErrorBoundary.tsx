import { Component, type ErrorInfo, type ReactNode } from 'react'
import { StatusScreen } from '../pages/StatusScreen'
import { statusButton } from '../pages/statusStyles'

/// Catches render-time errors anywhere below it and shows a calm fallback
/// instead of a blank white screen. Error boundaries must be class components —
/// there is no hook equivalent for `getDerivedStateFromError`. Wrap every entry
/// point with this.
export class ErrorBoundary extends Component<{ children: ReactNode }, { hasError: boolean }> {
  state = { hasError: false }

  static getDerivedStateFromError(): { hasError: boolean } {
    return { hasError: true }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // Surface it for diagnostics; Vercel captures console output in the build
    // logs and the browser console in the field. We never swallow it silently.
    console.error('Vitals website error:', error, info.componentStack)
  }

  render() {
    if (!this.state.hasError) return this.props.children
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
}
