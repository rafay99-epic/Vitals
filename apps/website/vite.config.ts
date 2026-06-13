import { defineConfig } from 'vite'
import { tanstackRouter } from '@tanstack/router-plugin/vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
// Single-page app: one HTML entry, client-side routing via TanStack Router.
// The router plugin must run before @vitejs/plugin-react. It generates
// src/routeTree.gen.ts from the files in src/routes/. appType stays the default
// 'spa' so dev/preview fall back to index.html for client routes — Vercel does
// the same via the rewrite in vercel.json.
export default defineConfig({
  plugins: [
    tanstackRouter({ target: 'react', autoCodeSplitting: true }),
    react(),
    tailwindcss(),
  ],
})
