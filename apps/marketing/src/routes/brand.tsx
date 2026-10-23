import { createFileRoute } from '@tanstack/react-router'
import Brand from '../pages/Brand'

/// Store artwork and downloads at `/brand`.
export const Route = createFileRoute('/brand')({
  component: Brand,
})
