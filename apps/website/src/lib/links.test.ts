import { expect, test } from 'bun:test'
import { DOWNLOAD_URL, RELEASES_URL, REPO, REPO_URL } from './links'

// The download button must keep pointing at the rolling "latest" asset —
// this is the contract with the release pipeline.
test('download URL always serves the newest DMG', () => {
  expect(DOWNLOAD_URL).toBe(`https://github.com/${REPO}/releases/latest/download/Vitals.dmg`)
})

test('URLs derive from the single repo constant', () => {
  expect(REPO_URL).toBe(`https://github.com/${REPO}`)
  expect(RELEASES_URL).toBe(`${REPO_URL}/releases`)
})
