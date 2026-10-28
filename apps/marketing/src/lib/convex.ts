import { ConvexReactClient } from 'convex/react'

/// The site reads the cached latest-release info from Convex when a deployment
/// URL is configured (`VITE_CONVEX_URL` — set in production and local dev). When
/// it isn't — CI builds, or anyone running the site without a backend — the app
/// falls back to fetching GitHub directly, so the landing page always works.
const url = import.meta.env.VITE_CONVEX_URL
export const convexEnabled = Boolean(url)
export const convex = url ? new ConvexReactClient(url) : null
