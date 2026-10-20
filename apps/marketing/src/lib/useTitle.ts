import { useEffect } from 'react'

/// Sets document.title for the lifetime of a route. In an SPA the title doesn't
/// change on its own between client navigations, so each page sets its own.
export function useTitle(title: string) {
  useEffect(() => {
    document.title = title
  }, [title])
}
