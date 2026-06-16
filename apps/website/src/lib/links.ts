export const REPO = 'rafay99-epic/Vitals'
export const REPO_URL = `https://github.com/${REPO}`
export const RELEASES_URL = `${REPO_URL}/releases`
// The /latest/download/ path always serves the asset from the newest release.
export const DOWNLOAD_URL = `${RELEASES_URL}/latest/download/Vitals.dmg`

// The Homebrew tap — the recommended install path (no Gatekeeper prompt).
export const BREW_TAP = 'rafay99-epic/apps'
export const BREW_INSTALL = `brew install --cask ${BREW_TAP}/vitals`
export const BREW_INSTALL_NIGHTLY = `brew install --cask ${BREW_TAP}/vitals-nightly`

export const COMPANY = 'Syntax Lab Technology'
export const DEVELOPER = 'Abdul Rafay'
export const DEVELOPER_URL = 'https://rafay99.com'
// Where the in-app "Report a Problem" flow sends diagnostic logs (user-initiated).
export const SUPPORT_EMAIL = '99marafay@gmail.com'
