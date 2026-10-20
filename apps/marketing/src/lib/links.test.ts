import { expect, test } from 'bun:test'
import { BREW_INSTALL, BREW_INSTALL_NIGHTLY, BREW_TAP, DOWNLOAD_URL, DOWNLOAD_URL_NIGHTLY, RELEASES_URL, REPO, REPO_URL } from './links'

// The download buttons must keep pointing at their rolling tags — this is the
// contract with the release pipeline. Stable → /latest; Nightly → the `nightly` tag.
test('download URLs always serve the newest DMGs', () => {
  expect(DOWNLOAD_URL).toBe(`https://github.com/${REPO}/releases/latest/download/Vitals.dmg`)
  expect(DOWNLOAD_URL_NIGHTLY).toBe(`https://github.com/${REPO}/releases/download/nightly/Vitals-Nightly.dmg`)
})

// The Homebrew casks: Stable installs `vitals`, Nightly installs `vitals-nightly`
// (the tap names the desktop updater + nightly.yml publish to).
test('Homebrew casks match the published channel names', () => {
  expect(BREW_INSTALL).toBe(`brew install --cask ${BREW_TAP}/vitals`)
  expect(BREW_INSTALL_NIGHTLY).toBe(`brew install --cask ${BREW_TAP}/vitals-nightly`)
})

test('URLs derive from the single repo constant', () => {
  expect(REPO_URL).toBe(`https://github.com/${REPO}`)
  expect(RELEASES_URL).toBe(`${REPO_URL}/releases`)
})
