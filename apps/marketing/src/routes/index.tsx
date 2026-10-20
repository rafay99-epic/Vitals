import { createFileRoute } from '@tanstack/react-router'
import App from '../App'

/// The landing page at `/`.
export const Route = createFileRoute('/')({
  component: App,
})
