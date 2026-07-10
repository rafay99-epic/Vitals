// ⚠️ DORMANT under TypeScript 7. This config is currently NOT run — the `lint`
// script in package.json skips ESLint because `typescript-eslint` has no
// TypeScript 7 support yet: its parser (`@typescript-eslint/typescript-estree`)
// needs the classic TS compiler API, which the TS7-native package removed
// (`require('typescript')` now exposes only `{ version }`). The code is still
// type-checked by `tsc -b` under TS7. To re-enable: bump `typescript-eslint` to a
// TS7-compatible release and restore `"lint": "eslint ."` in package.json. The
// config below is kept intact so that re-enable is a one-line change.
import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import tseslint from 'typescript-eslint'
import { defineConfig, globalIgnores } from 'eslint/config'

export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      js.configs.recommended,
      tseslint.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      globals: globals.browser,
    },
  },
])
