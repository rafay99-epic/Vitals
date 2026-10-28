/// <reference types="vite/client" />

interface ImportMetaEnv {
  /// The Convex deployment URL. Set in production and local dev; absent in CI
  /// builds, where the site falls back to fetching GitHub directly.
  readonly VITE_CONVEX_URL?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
