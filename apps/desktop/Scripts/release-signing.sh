#!/bin/bash
# One-time setup for signed + notarized releases (run on the maintainer's Mac).
#
#   ./Scripts/release-signing.sh csr
#       Makes a private key and a certificate signing request in ~/.vitals-signing.
#       Upload the .csr at developer.apple.com → Certificates → + →
#       "Developer ID Application" (G2 Sub-CA) and download the .cer.
#
#   ./Scripts/release-signing.sh upload <developerID.cer> <AuthKey_KEYID.p8> <issuer-id>
#       Bundles the key + certificate into a .p12, imports it into the login
#       keychain (so local `CODESIGN_IDENTITY=… ./build.sh` signs with it), and
#       sets the five repo secrets .github/scripts/setup-signing.sh reads. The .p8
#       is an App Store Connect API key (Users and Access → Integrations →
#       Team Keys, Developer role or higher); its Key ID is taken from the name.
#
# Requires: gh (logged in with access to the repo), /usr/bin/openssl.
set -euo pipefail
REPO="${VITALS_REPO:-rafay99-epic/Vitals}"
DIR="$HOME/.vitals-signing"
KEY="$DIR/developer-id.key"
OPENSSL=/usr/bin/openssl  # LibreSSL: writes a .p12 that `security import` reads

case "${1:-}" in
  csr)
    mkdir -p "$DIR" && chmod 700 "$DIR"
    if [ -f "$KEY" ]; then
      echo "Reusing $KEY"
    else
      (umask 077 && "$OPENSSL" genrsa -out "$KEY" 2048 2>/dev/null)
    fi
    "$OPENSSL" req -new -key "$KEY" -out "$DIR/developer-id.csr" \
      -subj "/CN=Vitals Developer ID/C=US"
    echo "CSR → $DIR/developer-id.csr"
    echo "Upload it: https://developer.apple.com/account/resources/certificates/add"
    ;;
  upload)
    CER="${2:?path to the downloaded developerID_application.cer}"
    P8="${3:?path to AuthKey_<KEYID>.p8}"
    ISSUER="${4:?App Store Connect issuer id}"
    [ -f "$KEY" ] || { echo "No $KEY; run '$0 csr' first." >&2; exit 1; }
    KEY_ID="$(basename "$P8" .p8)"; KEY_ID="${KEY_ID#AuthKey_}"
    # Check the notary key first, so a bad key never lands in the repo secrets.
    echo "Checking the notary key…"
    xcrun notarytool history --key "$P8" --key-id "$KEY_ID" --issuer "$ISSUER" >/dev/null
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    "$OPENSSL" x509 -inform DER -in "$CER" -out "$WORK/cert.pem"
    NAME="$("$OPENSSL" x509 -in "$WORK/cert.pem" -noout -subject -nameopt multiline | sed -n 's/^ *commonName *= //p')"
    case "$NAME" in
      "Developer ID Application:"*) ;;
      *) echo "$CER is \"$NAME\", not a Developer ID Application certificate." >&2; exit 1 ;;
    esac
    PW="$("$OPENSSL" rand -base64 24)"
    "$OPENSSL" pkcs12 -export -inkey "$KEY" -in "$WORK/cert.pem" -out "$WORK/signing.p12" \
      -name "$NAME" -passout "pass:$PW" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
    # Apple's Developer ID G2 intermediate completes the chain on a fresh Mac
    # (importing it again where it already exists is a harmless error).
    LOGIN="$HOME/Library/Keychains/login.keychain-db"
    curl --fail --silent --show-error --max-time 60 -o "$WORK/DeveloperIDG2CA.cer" \
      https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
    security import "$WORK/DeveloperIDG2CA.cer" -k "$LOGIN" >/dev/null 2>&1 || true
    security import "$WORK/signing.p12" -k "$LOGIN" -P "$PW" -T /usr/bin/codesign \
      || echo "note: already in the login keychain"
    security find-identity -v -p codesigning | grep -qF "\"$NAME\"" \
      || { echo "error: $NAME is not a valid signing identity in the login keychain" >&2; exit 1; }
    # Keep a copy of everything ./sign.sh and CI use, in one place.
    (umask 077
      cp "$WORK/signing.p12" "$DIR/developer-id.p12"
      printf '%s' "$PW" > "$DIR/p12-password.txt"
      printf '%s' "$ISSUER" > "$DIR/issuer.txt"
      printf '%s' "$NAME" > "$DIR/identity.txt"
      # One key at a time: a rotated key replaces the old one (./sign.sh needs exactly one).
      for old in "$DIR"/AuthKey_*.p8; do
        if [ -e "$old" ] && ! [ "$old" -ef "$P8" ]; then rm -f "$old"; fi
      done
      [ "$P8" -ef "$DIR/$(basename "$P8")" ] || cp "$P8" "$DIR/")
    base64 < "$WORK/signing.p12" | gh secret set MACOS_SIGN_CERT_P12 -R "$REPO"
    printf '%s' "$PW" | gh secret set MACOS_SIGN_CERT_PASSWORD -R "$REPO"
    gh secret set APPLE_API_KEY_P8 -R "$REPO" < "$P8"
    printf '%s' "$KEY_ID" | gh secret set APPLE_API_KEY_ID -R "$REPO"
    printf '%s' "$ISSUER" | gh secret set APPLE_API_ISSUER_ID -R "$REPO"
    echo "Done. Identity: $NAME"
    echo "Signed + notarized DMG locally: ./sign.sh nightly"
    ;;
  *)
    sed -n '2,15p' "$0"
    exit 1
    ;;
esac
