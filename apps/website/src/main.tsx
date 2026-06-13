import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { RouterProvider, createRouter } from '@tanstack/react-router'
import { ConvexProvider } from 'convex/react'
import './index.css'
import { ErrorBoundary } from './components/ErrorBoundary'
import { convex } from './lib/convex'
import { routeTree } from './routeTree.gen'

// `trailingSlash: 'never'` redirects the old MPA URLs (/terms/, /privacy/) to
// their slash-free routes, so existing links keep working.
const router = createRouter({ routeTree, trailingSlash: 'never' })

declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router
  }
}

// ConvexProvider is mounted only when a deployment URL is configured; otherwise
// the app runs without it and the release badge falls back to a direct fetch.
const app = <RouterProvider router={router} />

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      {convex ? <ConvexProvider client={convex}>{app}</ConvexProvider> : app}
    </ErrorBoundary>
  </StrictMode>,
)
