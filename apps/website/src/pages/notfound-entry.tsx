import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '../index.css'
import { ErrorBoundary } from '../components/ErrorBoundary'
import NotFound from './NotFound'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorBoundary>
      <NotFound />
    </ErrorBoundary>
  </StrictMode>,
)
