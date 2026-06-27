#!/bin/bash
# CI: import the stable self-signed signing cert into a throwaway keychain and
# export CODESIGN_IDENTITY (which build.sh reads) so released builds carry one
# stable signature — keeping users' TCC grants + Gatekeeper identity across
# auto-updates instead of resetting them every release.
#
# MUST run only in a trusted context (push to a protected/integration branch),
# NEVER in a pull_request job: a PR from a fork could read the secret. If the
# secrets are absent it warns and exits 0, so the build falls back to ad-hoc and
# a missing secret never fails a release.
set -euo pipefail
if [ -z "${MACOS_SIGN_CERT_P12:-}" ] || [ -z "${MACOS_SIGN_CERT_PASSWORD:-}" ]; then
  echo "::warning::MACOS_SIGN_CERT_P12/PASSWORD not set — building ad-hoc; released builds will need a manual permission re-grant on update."
  exit 0
fi
KEYCHAIN="$RUNNER_TEMP/app-signing.keychain-db"
KEYCHAIN_PW="$(openssl rand -base64 24)"
CERT_P12="$RUNNER_TEMP/app-signing.p12"
# Guarantee the decoded .p12 is removed even if a later step fails (the keychain is
# kept — the build needs it; the runner is ephemeral and discarded after the job).
trap 'rm -f "$CERT_P12"' EXIT
security create-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN"
echo "$MACOS_SIGN_CERT_P12" | base64 --decode > "$CERT_P12"
security import "$CERT_P12" -k "$KEYCHAIN" -P "$MACOS_SIGN_CERT_PASSWORD" -T /usr/bin/codesign
rm -f "$CERT_P12"
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PW" "$KEYCHAIN" >/dev/null
existing_keychains=()
while IFS= read -r kc; do
  kc="${kc//\"/}"; kc="${kc#"${kc%%[![:space:]]*}"}"
  [ -n "$kc" ] && existing_keychains+=("$kc")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KEYCHAIN" "${existing_keychains[@]}"
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)"
[ -n "$IDENTITY" ] || { echo "::error::No code-signing identity found after import."; exit 1; }
echo "CODESIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
echo "Configured stable signing identity: $IDENTITY"
