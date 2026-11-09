#!/bin/zsh
# Signed + notarized DMG on this Mac, with the same keys CI uses (kept in
# ~/.vitals-signing by Scripts/release-signing.sh). Nothing is installed or
# published; the DMG lands in build/.
#   ./sign.sh            Nightly DMG (default)
#   ./sign.sh stable     Stable DMG
#   ./sign.sh status     Apple's last few notarizations
set -euo pipefail
cd "$(dirname "$0")"

DIR="$HOME/.vitals-signing"
P8=("$DIR"/AuthKey_*.p8(N))
[ ${#P8} -eq 1 ] || { echo "Need exactly one AuthKey_*.p8 in $DIR (run Scripts/release-signing.sh)." >&2; exit 1; }
export NOTARY_KEY_PATH="${P8[1]}"
export NOTARY_KEY_ID="${${NOTARY_KEY_PATH:t:r}#AuthKey_}"
export NOTARY_ISSUER="$(<"$DIR/issuer.txt")"

if [ "${1:-}" = status ]; then
  xcrun notarytool history --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" | sed -n '1,20p'
  exit 0
fi

CHANNEL="${1:-nightly}"
# The identity release-signing.sh imported, so another team's certificate in the
# keychain is never picked by accident.
export CODESIGN_IDENTITY="$(<"$DIR/identity.txt")"
case "$CHANNEL" in
  stable)  APP="build/Vitals.app" ;;
  nightly) APP="build/Vitals Nightly.app" ;;
  *) echo "usage: ./sign.sh [nightly|stable|status]" >&2; exit 1 ;;
esac

# Sign from a throwaway keychain holding the same .p12 CI uses, unlocked and
# open to codesign, so no "codesign wants to use your key" dialog blocks a
# headless run. Removed on exit; the login keychain is untouched.
export CODESIGN_KEYCHAIN="$(mktemp -d)/sign.keychain-db"
KC_PW="$(openssl rand -base64 24)"
trap 'security delete-keychain "$CODESIGN_KEYCHAIN" 2>/dev/null; rm -rf "${CODESIGN_KEYCHAIN:h}"' EXIT
security create-keychain -p "$KC_PW" "$CODESIGN_KEYCHAIN"
security set-keychain-settings -lut 21600 "$CODESIGN_KEYCHAIN"  # no 5-minute idle lock mid-build
security unlock-keychain -p "$KC_PW" "$CODESIGN_KEYCHAIN"
security import "$DIR/developer-id.p12" -k "$CODESIGN_KEYCHAIN" -P "$(<"$DIR/p12-password.txt")" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PW" "$CODESIGN_KEYCHAIN" >/dev/null
# Apple's Developer ID G2 intermediate completes the chain, as in CI, so a clean
# Mac needs nothing else installed. The identity is checked in this keychain,
# the one codesign actually signs from.
curl --fail --silent --show-error --max-time 60 -o "${CODESIGN_KEYCHAIN:h}/DeveloperIDG2CA.cer" \
  https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
security import "${CODESIGN_KEYCHAIN:h}/DeveloperIDG2CA.cer" -k "$CODESIGN_KEYCHAIN" >/dev/null
IDENTITIES="$(security find-identity -v -p codesigning "$CODESIGN_KEYCHAIN")"
grep -qF "\"$CODESIGN_IDENTITY\"" <<< "$IDENTITIES" \
  || { echo "\"$CODESIGN_IDENTITY\" is not a valid identity in $DIR/developer-id.p12." >&2; exit 1; }

# make-dmg.sh only builds when the app is missing; rebuild so it's this checkout, signed.
rm -rf "$APP"
VITALS_CHANNEL="$CHANNEL" ./make-dmg.sh
spctl -a -t open --context context:primary-signature -vv "build/$([ "$CHANNEL" = stable ] && echo Vitals || echo Vitals-Nightly).dmg"
