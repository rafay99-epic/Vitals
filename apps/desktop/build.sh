#!/bin/zsh
# Builds the app from scratch. Usage: ./build.sh
#   VITALS_CHANNEL=stable (default) → Vitals.app           com.syntaxlabtechnology.vitals
#   VITALS_CHANNEL=nightly          → "Vitals Nightly.app" com.syntaxlabtechnology.vitals.nightly
#   VITALS_CHANNEL=dev              → "Vitals Dev.app"      com.syntaxlabtechnology.vitals.dev
# The channels install side by side (different bundle id + name + data + icon).
# Stable + Nightly auto-update from GitHub releases; Dev never does. CI builds
# Stable (ci.yml, no env var); nightly.yml builds Nightly.
set -euo pipefail
cd "$(dirname "$0")"

# SwiftUI's property-wrapper macros (for example @State) are provided by the
# full Xcode toolchain. Command Line Tools can expose a Swift compiler while
# still failing later with the misleading "SwiftUIMacros plugin not found"
# error, so stop here with the actual fix.
DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
if [[ -z "$DEVELOPER_DIR_PATH" || ! -x "$DEVELOPER_DIR_PATH/usr/bin/xcodebuild" ]]; then
  echo "Vitals requires full Xcode to build SwiftUI." >&2
  echo "Active developer directory: ${DEVELOPER_DIR_PATH:-<none>}" >&2
  echo "Install Xcode 16 or newer, then select it with:" >&2
  echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

CHANNEL="${VITALS_CHANNEL:-stable}"
case "$CHANNEL" in
  stable)
    APP_NAME="Vitals"
    BUNDLE_ID="com.syntaxlabtechnology.vitals"
    ICON_CACHE="Resources/AppIcon.icns"
    ;;
  nightly)
    APP_NAME="Vitals Nightly"
    BUNDLE_ID="com.syntaxlabtechnology.vitals.nightly"
    ICON_CACHE="Resources/AppIcon-Nightly.icns"
    ;;
  dev)
    APP_NAME="Vitals Dev"
    BUNDLE_ID="com.syntaxlabtechnology.vitals.dev"
    ICON_CACHE="Resources/AppIcon-Dev.icns"
    ;;
  *)
    echo "VITALS_CHANNEL must be 'stable', 'nightly', or 'dev' (got '$CHANNEL')" >&2
    exit 1
    ;;
esac

echo "Compiling arm64 (Apple Silicon)…  [channel: $CHANNEL]"
# Vitals uses Apple Silicon-only sensors and is not distributed for Intel Macs.
# Keeping this explicit prevents SwiftPM from producing a deprecated x86_64
# slice when the active SDK starts warning about Intel deployment support.
swift build -c release --arch arm64
BINARY="$(swift build --show-bin-path -c release --arch arm64)/Vitals"
if [[ ! -x "$BINARY" ]]; then
  echo "error: SwiftPM did not produce the expected executable: $BINARY" >&2
  exit 1
fi
ARCH_INFO="$(lipo -info "$BINARY")"
echo "Binary architecture: $ARCH_INFO"
if [[ "$ARCH_INFO" != *"arm64"* || "$ARCH_INFO" == *"x86_64"* ]]; then
  echo "error: expected an arm64-only Vitals binary" >&2
  exit 1
fi

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Vitals"
cp Resources/Info.plist "$APP/Contents/Info.plist"

PB=/usr/libexec/PlistBuddy
# Version is 0.<total commit count> — 10 commits → 0.10. CI passes
# VITALS_VERSION; local builds compute it from the repo. Nightly and Dev append
# a channel suffix (-nightly / -dev) and stamp the exact branch@sha so the About
# screen shows what's running. Stable ships a clean numeric version.
COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
VERSION="${VITALS_VERSION:-0.$COMMIT_COUNT}"
if [[ "$CHANNEL" != "stable" ]]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
  VERSION="$VERSION-$CHANNEL"
  "$PB" -c "Add :VitalsBuildInfo string $BRANCH@$SHA" "$APP/Contents/Info.plist" 2>/dev/null \
    || "$PB" -c "Set :VitalsBuildInfo $BRANCH@$SHA" "$APP/Contents/Info.plist"
fi
"$PB" -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
"$PB" -c "Add :CFBundleDisplayName string $APP_NAME" "$APP/Contents/Info.plist" 2>/dev/null \
  || "$PB" -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"
"$PB" -c "Set :VitalsChannel $CHANNEL" "$APP/Contents/Info.plist"
# Monotonic build number (CI run number) — orders Nightly pre-releases for the
# updater. Absent/0 for local builds.
if [ -n "${VITALS_BUILD:-}" ]; then
  "$PB" -c "Add :VitalsBuildNumber string $VITALS_BUILD" "$APP/Contents/Info.plist" 2>/dev/null \
    || "$PB" -c "Set :VitalsBuildNumber $VITALS_BUILD" "$APP/Contents/Info.plist"
fi
echo "Version $VERSION  ($APP_NAME · $BUNDLE_ID)"

# Generate the channel's icon once; delete the cache file to force a re-render.
if [ ! -f "$ICON_CACHE" ]; then
  echo "Rendering $CHANNEL icon…"
  PNG="/tmp/vitals_icon_${CHANNEL}_1024.png"
  swift Scripts/MakeIcon.swift "$PNG" "$CHANNEL"
  ICONSET="/tmp/Vitals-$CHANNEL.iconset"
  rm -rf "$ICONSET" && mkdir "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$PNG" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ICON_CACHE"
fi
cp "$ICON_CACHE" "$APP/Contents/Resources/AppIcon.icns"

# Code signing. Default is ad-hoc (`-`), which is fine for a local build but
# produces a *different* signature every time — and macOS keys TCC grants
# (Accessibility / Microphone / Screen Recording) and Gatekeeper identity to the
# signature, so an ad-hoc update looks like a brand-new app and silently drops
# every permission. Set CODESIGN_IDENTITY to a stable self-signed cert (see
# Scripts/make-signing-cert.sh) and every build shares one designated requirement,
# so the grant persists across updates. CI exports it from a secret on releases
# only (.github/scripts/setup-signing.sh). No Apple account / notarization.
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$SIGN_IDENTITY" != "-" ]; then
  SIGN_IDENTITIES="$(security find-identity -p codesigning 2>/dev/null || true)"
  if ! grep -qF "\"$SIGN_IDENTITY\"" <<< "$SIGN_IDENTITIES"; then
    echo "CODESIGN_IDENTITY=\"$SIGN_IDENTITY\" not found in keychain; falling back to ad-hoc." >&2
    SIGN_IDENTITY="-"
  fi
fi
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  echo "Signing with stable identity: $SIGN_IDENTITY (TCC grant persists across builds)"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
fi
echo "Done → $PWD/$APP"
