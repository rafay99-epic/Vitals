import { createFileRoute } from '@tanstack/react-router'
import Releases from '../pages/Releases'

/// All published releases at `/releases`.
export const Route = createFileRoute('/releases')({
  component: Releases,
})
