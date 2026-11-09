#!/bin/bash
# CI: set up Developer ID signing and notarization for a published build.
# Imports the team's Developer ID Application certificate into a throwaway
# keychain and exports CODESIGN_IDENTITY (build.sh + make-dmg.sh sign with it),
# then writes the App Store Connect API key and exports NOTARY_* (make-dmg.sh
# notarizes and staples the DMG with it).
#
# Secrets (set them with apps/desktop/Scripts/release-signing.sh):
#   MACOS_SIGN_CERT_P12        base64 of the Developer ID Application .p12
#   MACOS_SIGN_CERT_PASSWORD   its password
#   APPLE_API_KEY_P8           the App Store Connect API key (.p8 contents)
#   APPLE_API_KEY_ID           its Key ID
#   APPLE_API_ISSUER_ID        its Issuer ID
#
# MUST run only in a trusted context (push to `main` / `nightly`), NEVER in a
# pull_request job: a PR from a fork could read the secrets. Any missing secret
# fails the job: releases are only ever Developer ID signed and notarized, never
# ad-hoc, and a signed build that isn't notarized is blocked by Gatekeeper.
set -euo pipefail
if [ -z "${MACOS_SIGN_CERT_P12:-}" ] || [ -z "${MACOS_SIGN_CERT_PASSWORD:-}" ]; then
  echo "::error::MACOS_SIGN_CERT_P12/PASSWORD not set; releases must be signed and notarized."
  exit 1
fi
if [ -z "${APPLE_API_KEY_P8:-}" ] || [ -z "${APPLE_API_KEY_ID:-}" ] || [ -z "${APPLE_API_ISSUER_ID:-}" ]; then
  echo "::error::APPLE_API_KEY_P8 / APPLE_API_KEY_ID / APPLE_API_ISSUER_ID not set; a signed build must be notarized."
  exit 1
fi

KEYCHAIN="$RUNNER_TEMP/app-signing.keychain-db"
KEYCHAIN_PW="$(openssl rand -base64 24)"
CERT_P12="$RUNNER_TEMP/app-signing.p12"
INTERMEDIATE="$RUNNER_TEMP/DeveloperIDG2CA.cer"
# Remove the decoded .p12 even if a later step fails (the keychain stays for the
# build; the runner is ephemeral and discarded after the job).
trap 'rm -f "$CERT_P12"' EXIT
security create-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN"
echo "$MACOS_SIGN_CERT_P12" | base64 --decode > "$CERT_P12"
security import "$CERT_P12" -k "$KEYCHAIN" -P "$MACOS_SIGN_CERT_PASSWORD" -T /usr/bin/codesign
rm -f "$CERT_P12"
# The .p12 holds only the leaf; codesign needs Apple's Developer ID intermediate
# to build the chain it embeds.
curl --fail --silent --show-error --max-time 60 -o "$INTERMEDIATE" \
  https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
security import "$INTERMEDIATE" -k "$KEYCHAIN" >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PW" "$KEYCHAIN" >/dev/null
existing_keychains=()
while IFS= read -r kc; do
  kc="${kc//\"/}"; kc="${kc#"${kc%%[![:space:]]*}"}"
  [ -n "$kc" ] && existing_keychains+=("$kc")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KEYCHAIN" "${existing_keychains[@]}"

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p' | head -1)"
[ -n "$IDENTITY" ] || { echo "::error::No valid Developer ID Application identity in MACOS_SIGN_CERT_P12."; exit 1; }
echo "CODESIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
echo "Signing identity: $IDENTITY"

KEY_PATH="$RUNNER_TEMP/AuthKey_${APPLE_API_KEY_ID}.p8"
printf '%s\n' "$APPLE_API_KEY_P8" > "$KEY_PATH"
chmod 600 "$KEY_PATH"
{
  echo "NOTARY_KEY_PATH=$KEY_PATH"
  echo "NOTARY_KEY_ID=$APPLE_API_KEY_ID"
  echo "NOTARY_ISSUER=$APPLE_API_ISSUER_ID"
} >> "$GITHUB_ENV"
echo "Notarization: App Store Connect key $APPLE_API_KEY_ID"
