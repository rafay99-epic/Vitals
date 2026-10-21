import { createFileRoute } from '@tanstack/react-router'
import Privacy from '../pages/Privacy'

/// Privacy Policy at `/privacy`.
export const Route = createFileRoute('/privacy')({
  component: Privacy,
})
