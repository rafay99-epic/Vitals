import { createFileRoute } from '@tanstack/react-router'
import Terms from '../pages/Terms'

/// Terms & Conditions at `/terms`.
export const Route = createFileRoute('/terms')({
  component: Terms,
})
