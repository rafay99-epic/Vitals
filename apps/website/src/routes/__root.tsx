import { createRootRoute } from '@tanstack/react-router'
import RootLayout from '../components/RootLayout'
import NotFound from '../pages/NotFound'
import ErrorScreen from '../pages/ErrorScreen'

/// The root route wraps every page. A path that matches no route renders the
/// 404 page; an error thrown inside a route renders the error page — both keep
/// the user inside the app instead of showing a blank screen.
export const Route = createRootRoute({
  component: RootLayout,
  notFoundComponent: NotFound,
  errorComponent: ErrorScreen,
})
