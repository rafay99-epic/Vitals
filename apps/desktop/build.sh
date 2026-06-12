#!/bin/zsh
# Builds Vitals.app from scratch. Usage: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "Compiling universal (arm64 + x86_64)…"
# Universal so the app can launch on an Intel Mac far enough to show its
# "Apple Silicon only" apology; the real features run on the arm64 slice.
swift build -c release --arch arm64 --arch x86_64
BINARY=".build/apple/Products/Release/Vitals"

APP="build/Vitals.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Vitals"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Version is 0.<total commit count> — 10 commits → 0.10. CI passes
# VITALS_VERSION; local builds compute it from the repo.
COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
VERSION="${VITALS_VERSION:-0.$COMMIT_COUNT}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
echo "Version $VERSION"

# Generate the icon once; delete Resources/AppIcon.icns to force a re-render.
if [ ! -f Resources/AppIcon.icns ]; then
  echo "Rendering icon…"
  swift Scripts/MakeIcon.swift /tmp/vitals_icon_1024.png
  ICONSET=/tmp/Vitals.iconset
  rm -rf "$ICONSET" && mkdir "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s /tmp/vitals_icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d /tmp/vitals_icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Done → $PWD/$APP"
