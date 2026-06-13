// End-to-end checks against the built site (dist/), driven through a
// headless Chromium-based browser. Verifies the pages render, the mobile
// layout has no horizontal overflow, and the download contract holds.
//
// Requires a prior build. Uses the system browser (no downloads):
// Chrome/Chromium on CI, Chrome or Brave locally — or set E2E_BROWSER.
import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { chromium } from 'playwright-core'

const websiteDir = fileURLToPath(new URL('..', import.meta.url))
const PORT = 4317
const BASE = `http://localhost:${PORT}`

const browserCandidates = [
  process.env.E2E_BROWSER,
  '/usr/bin/google-chrome',
  '/usr/bin/chromium-browser',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
].filter(Boolean)

const executablePath = browserCandidates.find((p) => existsSync(p))
if (!executablePath) {
  console.error('e2e: no Chromium-based browser found — set E2E_BROWSER to a browser binary')
  process.exit(1)
}
if (!existsSync(`${websiteDir}/dist/index.html`)) {
  console.error('e2e: dist/ missing — run the build first')
  process.exit(1)
}

const server = spawn('bun', ['run', 'preview', '--port', String(PORT), '--strictPort'], {
  cwd: websiteDir,
  stdio: 'ignore',
})

async function waitForServer() {
  for (let i = 0; i < 50; i++) {
    try {
      const res = await fetch(BASE)
      if (res.ok) return
    } catch {
      /* not up yet */
    }
    await new Promise((r) => setTimeout(r, 200))
  }
  throw new Error('preview server did not start')
}

let failures = 0
function check(name, ok, detail = '') {
  if (ok) {
    console.log(`  ✓ ${name}`)
  } else {
    failures++
    console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`)
  }
}

try {
  await waitForServer()
  console.log(`e2e: using browser at ${executablePath}`)
  const browser = await chromium.launch({
    executablePath,
    headless: true,
    // CI runners (and containers) often need these for Chrome to start.
    args: process.env.CI ? ['--no-sandbox', '--disable-dev-shm-usage'] : [],
  })
  const page = await browser.newPage()

  // --- Landing page, mobile (iPhone width) ---
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto(BASE, { waitUntil: 'networkidle' })
  console.log('mobile (390px):')
  check('page loads with Vitals title', (await page.title()).includes('Vitals'))
  const mobileScroll = await page.evaluate(() => document.documentElement.scrollWidth)
  check('no horizontal overflow', mobileScroll === 390, `scrollWidth ${mobileScroll}`)
  check(
    'live sparklines render points',
    await page.evaluate(() => {
      const poly = document.querySelector('polyline[points]')
      return Boolean(poly && poly.getAttribute('points').length > 10)
    }),
  )

  // --- Landing page, desktop ---
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto(BASE, { waitUntil: 'networkidle' })
  console.log('desktop (1440px):')
  const desktopScroll = await page.evaluate(() => document.documentElement.scrollWidth)
  check('no horizontal overflow', desktopScroll === 1440, `scrollWidth ${desktopScroll}`)
  const dmgLinks = await page.evaluate(() =>
    [...document.querySelectorAll('a')].map((a) => a.href).filter((h) => h.endsWith('/releases/latest/download/Vitals.dmg')),
  )
  check('download button serves the latest DMG', dmgLinks.length >= 1, `found ${dmgLinks.length}`)
  check(
    'footer credits Syntax Lab Technology',
    await page.evaluate(() => document.body.textContent.includes('Syntax Lab Technology')),
  )

  // --- Legal pages ---
  for (const [path, expected] of [
    ['/terms/', 'Terms & Conditions'],
    ['/privacy/', 'Privacy Policy'],
  ]) {
    await page.goto(`${BASE}${path}`, { waitUntil: 'networkidle' })
    console.log(`${path}:`)
    check(`renders "${expected}"`, await page.evaluate((t) => document.body.textContent.includes(t), expected))
    check(
      'names the company',
      await page.evaluate(() => document.body.textContent.includes('Syntax Lab Technology')),
    )
  }

  // --- 404 page ---
  // The page itself lives at /404.html; Vercel serves it (with a 404 status)
  // for any unmatched path. Preview can't reproduce Vercel's body-for-404, so
  // we check the page content at /404.html and the 404 *status* separately.
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto(`${BASE}/404.html`, { waitUntil: 'networkidle' })
  console.log('/404.html:')
  check('renders the not-found message', await page.evaluate(() => document.body.textContent.includes('This page isn’t here')))
  check('offers a way back to Vitals', await page.evaluate(() => [...document.querySelectorAll('a')].some((a) => a.textContent.includes('Back to Vitals'))))
  check('names the company', await page.evaluate(() => document.body.textContent.includes('Syntax Lab Technology')))
  const notFoundScroll = await page.evaluate(() => document.documentElement.scrollWidth)
  check('no horizontal overflow', notFoundScroll === 390, `scrollWidth ${notFoundScroll}`)

  // A real request (not a navigation — page.goto throws on a bodyless 404).
  const unmatched = await page.request.get(`${BASE}/no-such-page-xyz`)
  console.log('/no-such-page-xyz:')
  check('unmatched path returns a 404 status', unmatched.status() === 404, `status ${unmatched.status()}`)

  await browser.close()
} catch (error) {
  failures++
  console.error(`e2e: ${error.message}`)
} finally {
  server.kill()
}

if (failures > 0) {
  console.error(`\ne2e: ${failures} check(s) failed`)
  process.exit(1)
}
console.log('\ne2e: all checks passed')
