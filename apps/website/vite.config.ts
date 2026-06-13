import { resolve } from 'node:path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  // This is a multi-page site, not an SPA: an unmatched path is a real 404,
  // not a rewrite to index.html. 'mpa' makes dev/preview serve 404.html for
  // unknown routes, matching how Vercel serves the built dist/404.html.
  appType: 'mpa',
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html'),
        terms: resolve(__dirname, 'terms/index.html'),
        privacy: resolve(__dirname, 'privacy/index.html'),
        // Built to dist/404.html — Vercel serves it for any unmatched path.
        notFound: resolve(__dirname, '404.html'),
      },
    },
  },
})
