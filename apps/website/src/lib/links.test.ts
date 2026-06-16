import { expect, test } from 'bun:test'
import { BREW_INSTALL, BREW_INSTALL_NIGHTLY, BREW_TAP, DOWNLOAD_URL, RELEASES_URL, REPO, REPO_URL } from './links'

// The download button must keep pointing at the rolling "latest" asset —
// this is the contract with the release pipeline.
test('download URL always serves the newest DMG', () => {
  expect(DOWNLOAD_URL).toBe(`https://github.com/${REPO}/releases/latest/download/Vitals.dmg`)
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
