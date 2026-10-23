// Renders the store artwork in compose.html to PNGs under public/brand, then zips the kits.
// Run from apps/marketing on macOS: `bun run brand` (uses the system Chrome or Brave, or E2E_BROWSER).
// macOS only: icons go through `sips`, and the kits need `zip` on PATH.
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, rmSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { chromium } from 'playwright-core'

if (process.platform !== 'darwin') throw new Error('render: needs macOS (sips) for the store icons')

const composeUrl = new URL('compose.html', import.meta.url).href
const outDir = fileURLToPath(new URL('../public/brand/', import.meta.url))
const iconSource = fileURLToPath(new URL('../../mobile/assets/icon.png', import.meta.url))

const executablePath = [
  process.env.E2E_BROWSER,
  '/usr/bin/google-chrome',
  '/usr/bin/chromium-browser',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
]
  .filter(Boolean)
  .find((p) => existsSync(p))
if (!executablePath) throw new Error('render: no Chromium-based browser found, set E2E_BROWSER')

const shots = [1, 2, 3, 4, 5, 6]
const ASSETS = [
  { a: 'feature', file: 'android/feature-graphic.png', width: 1024, height: 500 },
  ...shots.map((n) => ({ a: `play-${n}`, file: `android/screenshot-${n}.png`, width: 1080, height: 1920 })),
  ...shots.map((n) => ({ a: `ios-${n}`, file: `ios/screenshot-${n}.png`, width: 1320, height: 2868 })),
]

rmSync(outDir, { recursive: true, force: true })
mkdirSync(`${outDir}android`, { recursive: true })
mkdirSync(`${outDir}ios`, { recursive: true })

const browser = await chromium.launch({ executablePath })
for (const asset of ASSETS) {
  const page = await browser.newPage({ viewport: { width: asset.width, height: asset.height } })
  await page.goto(`${composeUrl}?a=${asset.a}`)
  await page.waitForSelector('body[data-ready]')
  // Background images load lazily, so wait for every capture the page references.
  await page.waitForLoadState('networkidle')
  await page.screenshot({ path: `${outDir}${asset.file}` })
  await page.close()
  console.log('rendered', asset.file)
}
await browser.close()

// Store icons: Play wants 512x512, the App Store 1024x1024. Both reject an alpha channel, so flatten
// through a best-quality JPEG and back to PNG.
const icon = (size, file) => {
  const jpg = `${outDir}${file}.jpg`
  execFileSync('sips', ['-z', String(size), String(size), '-s', 'format', 'jpeg', '-s', 'formatOptions', 'best', iconSource, '--out', jpg], { stdio: 'ignore' })
  execFileSync('sips', ['-s', 'format', 'png', jpg, '--out', `${outDir}${file}`], { stdio: 'ignore' })
  rmSync(jpg)
}
icon(512, 'android/icon-512.png')
icon(1024, 'ios/icon-1024.png')

const zip = (name, ...paths) => execFileSync('zip', ['-qr', name, ...paths], { cwd: outDir })
zip('vitals-android.zip', 'android')
zip('vitals-ios.zip', 'ios')
zip('vitals-brand.zip', 'android', 'ios')
console.log('zipped kits into', outDir)
