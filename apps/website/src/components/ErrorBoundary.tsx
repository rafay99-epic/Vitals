import { Component, type ErrorInfo, type ReactNode } from 'react'
import ErrorScreen from '../pages/ErrorScreen'

/// Final safety net around the whole app. The router has its own errorComponent
/// for errors thrown inside a route; this catches anything outside that — a
/// failure in the router itself or in the root render. Error boundaries must be
/// class components: there is no hook equivalent for getDerivedStateFromError.
export class ErrorBoundary extends Component<{ children: ReactNode }, { hasError: boolean }> {
  state = { hasError: false }

  static getDerivedStateFromError(): { hasError: boolean } {
    return { hasError: true }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // Surface it for diagnostics — never swallow it silently.
    console.error('Vitals website error:', error, info.componentStack)
  }

  render() {
    if (this.state.hasError) return <ErrorScreen />
    return this.props.children
  }
}
