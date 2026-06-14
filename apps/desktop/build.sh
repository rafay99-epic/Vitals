#!/bin/zsh
# Builds the app from scratch. Usage: ./build.sh
#   VITALS_CHANNEL=stable (default) → Vitals.app          com.syntaxlabtechnology.vitals
#   VITALS_CHANNEL=dev              → "Vitals Dev.app"     com.syntaxlabtechnology.vitals.dev
# The two channels install side by side (different bundle id + name + data +
# icon); Dev never auto-updates. CI builds Stable (no env var set).
set -euo pipefail
cd "$(dirname "$0")"

CHANNEL="${VITALS_CHANNEL:-stable}"
if [[ "$CHANNEL" != "stable" && "$CHANNEL" != "dev" ]]; then
  echo "VITALS_CHANNEL must be 'stable' or 'dev' (got '$CHANNEL')" >&2
  exit 1
fi

if [[ "$CHANNEL" == "dev" ]]; then
  APP_NAME="Vitals Dev"
  BUNDLE_ID="com.syntaxlabtechnology.vitals.dev"
  ICON_CACHE="Resources/AppIcon-Dev.icns"
else
  APP_NAME="Vitals"
  BUNDLE_ID="com.syntaxlabtechnology.vitals"
  ICON_CACHE="Resources/AppIcon.icns"
fi

echo "Compiling universal (arm64 + x86_64)…  [channel: $CHANNEL]"
# Universal so the app can launch on an Intel Mac far enough to show its
# "Apple Silicon only" apology; the real features run on the arm64 slice.
swift build -c release --arch arm64 --arch x86_64
BINARY=".build/apple/Products/Release/Vitals"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Vitals"
cp Resources/Info.plist "$APP/Contents/Info.plist"

PB=/usr/libexec/PlistBuddy
# Version is 0.<total commit count> — 10 commits → 0.10. CI passes
# VITALS_VERSION; local builds compute it from the repo. Dev appends -dev and
# stamps the exact branch@sha so the About screen shows what's running.
COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
VERSION="${VITALS_VERSION:-0.$COMMIT_COUNT}"
if [[ "$CHANNEL" == "dev" ]]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
  VERSION="$VERSION-dev"
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
# Monotonic build number (CI run number) — orders Dev pre-releases for the
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

codesign --force --sign - "$APP"
echo "Done → $PWD/$APP"
