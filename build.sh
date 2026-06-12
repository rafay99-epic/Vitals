#!/bin/zsh
# Builds Vitals.app from scratch. Usage: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "Compiling…"
swift build -c release

APP="build/Vitals.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Vitals "$APP/Contents/MacOS/Vitals"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Stamp the version: CI sets VITALS_VERSION (base.run_number); local builds
# get base.0 so any published release counts as newer.
VERSION="${VITALS_VERSION:-$(cat VERSION).0}"
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
