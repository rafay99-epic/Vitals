import { Analytics } from '@vercel/analytics/react'
import { Outlet } from '@tanstack/react-router'

/// The shell rendered around every route: the active page through <Outlet/>,
/// plus Vercel Web Analytics mounted once for the whole SPA (the privacy policy
/// discloses this).
export default function RootLayout() {
  return (
    <>
      <Outlet />
      <Analytics />
    </>
  )
}
