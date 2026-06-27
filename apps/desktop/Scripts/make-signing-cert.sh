#!/bin/bash
# Generates a stable self-signed code-signing certificate for Vitals.
#
# Why: ad-hoc signatures (`codesign --sign -`) change every build, and macOS keys
# TCC grants (Accessibility / Microphone / Screen Recording) and Gatekeeper
# identity to the signature — so every ad-hoc update looks like a new app and
# silently drops permissions. A stable self-signed cert gives every build the
# same designated requirement, so the grant persists across updates. No Apple
# account, no notarization.
#
# Run once on a Mac. It imports the cert into your login keychain (so local
# `CODESIGN_IDENTITY="Vitals Local Signing" ./build.sh` works) and prints the two
# values to add as CI secrets (MACOS_SIGN_CERT_P12 + MACOS_SIGN_CERT_PASSWORD).
# The SAME cert/.p12 can be reused across every app in this family (Vitals,
# Porter, Quill, …) — generate it once, paste the same secrets into each repo.
set -euo pipefail
IDENTITY_NAME="${CODESIGN_IDENTITY:-Vitals Local Signing}"
# Allowlist the identity name (letters, digits, space, . _ -) so it can't inject
# newlines or OpenSSL-config metacharacters when written into req.cnf below.
case "$IDENTITY_NAME" in
  *[!A-Za-z0-9._\ -]*|"")
    echo "CODESIGN_IDENTITY must be non-empty and contain only letters, digits, spaces, '.', '_', '-'." >&2
    exit 1 ;;
esac
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
KEY="$WORK/key.pem"; CERT="$WORK/cert.pem"; P12="$WORK/signing.p12"
read -r -s -p "Choose a password for the exported .p12 (the CI secret): " P12_PW; echo
[ -n "$P12_PW" ] || { echo "Password cannot be empty." >&2; exit 1; }
# Pass the subject via a config file rather than `-subj`, so the CN is taken
# literally — no DN-separator escaping needed for `/`, `\`, `+`, `,`, `=`, etc.
REQ_CONF="$WORK/req.cnf"
cat > "$REQ_CONF" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3
[dn]
CN = $IDENTITY_NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
# Keep stderr visible (only silence stdout) so cert-generation failures are diagnosable.
openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" -days 3650 -nodes \
  -config "$REQ_CONF" >/dev/null
P12_PW="$P12_PW" openssl pkcs12 -export -inkey "$KEY" -in "$CERT" -out "$P12" \
  -name "$IDENTITY_NAME" -passout env:P12_PW \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
security import "$P12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$P12_PW" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$CERT" 2>/dev/null \
  || echo "Note: could not auto-add trust; you may get a one-time keychain prompt on first sign."
echo; echo "Local: CODESIGN_IDENTITY=\"$IDENTITY_NAME\" <build cmd>"
echo "Secrets: MACOS_SIGN_CERT_PASSWORD=(password); MACOS_SIGN_CERT_P12=base64 below:"
base64 < "$P12"
