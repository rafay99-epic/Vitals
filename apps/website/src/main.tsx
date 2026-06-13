import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { RouterProvider, createRouter } from '@tanstack/react-router'
import './index.css'
import { ErrorBoundary } from './components/ErrorBoundary'
import { routeTree } from './routeTree.gen'

// `trailingSlash: 'never'` redirects the old MPA URLs (/terms/, /privacy/) to
// their slash-free routes, so existing links keep working.
const router = createRouter({ routeTree, trailingSlash: 'never' })

declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router
  }
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <RouterProvider router={router} />
    </ErrorBoundary>
  </StrictMode>,
)
