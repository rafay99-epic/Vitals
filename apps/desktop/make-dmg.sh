#!/bin/zsh
# Packages the built app into a polished drag-to-install disk image.
#   VITALS_CHANNEL=stable (default) → build/Vitals.dmg         (Vitals.app)
#   VITALS_CHANNEL=nightly          → build/Vitals-Nightly.dmg ("Vitals Nightly.app")
# Dev is local-only and publishes no DMG (use ./dev.sh). Runs ./build.sh first
# if the app is missing.
set -euo pipefail
cd "$(dirname "$0")"

CHANNEL="${VITALS_CHANNEL:-stable}"
case "$CHANNEL" in
  stable)
    APP_NAME="Vitals"
    VOLUME="Vitals"
    OUT_DMG="build/Vitals.dmg"
    ;;
  nightly)
    APP_NAME="Vitals Nightly"
    VOLUME="Vitals Nightly"
    OUT_DMG="build/Vitals-Nightly.dmg"
    ;;
  dev)
    echo "Dev is local-only and publishes no DMG — use ./dev.sh instead." >&2
    exit 1
    ;;
  *)
    echo "VITALS_CHANNEL must be 'stable' or 'nightly' (got '$CHANNEL')" >&2
    exit 1
    ;;
esac

APP="build/$APP_NAME.app"
[ -d "$APP" ] || VITALS_CHANNEL="$CHANNEL" ./build.sh

STAGE="build/dmg-stage"
RW_DMG="build/Vitals-rw.dmg"

echo "Rendering installer background…"
swift Scripts/MakeDMGBackground.swift build/dmg-background.png

rm -rf "$STAGE" "$RW_DMG" "$OUT_DMG"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/$APP_NAME.app"
cp build/dmg-background.png "$STAGE/.background/background.png"
# Use this channel's own icon as the volume icon.
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
ln -s /Applications "$STAGE/Applications"

echo "Creating writable image…"
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -ov -fs HFS+ -format UDRW "$RW_DMG" >/dev/null

echo "Mounting for Finder layout…"
DEVICE=$(hdiutil attach "$RW_DMG" -noautoopen | awk '/\/Volumes\//{print $1; exit}')
trap 'hdiutil detach "$DEVICE" >/dev/null 2>&1 || true' EXIT

# Mark the volume as having a custom icon (.VolumeIcon.icns).
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "/Volumes/$VOLUME" || true
fi

# Window size, icon positions, and background. If Finder automation is not
# permitted (e.g. some CI runners), the DMG still works with default layout.
# Unquoted heredoc so $VOLUME / $APP_NAME interpolate (AppleScript has no $).
if ! osascript <<EOF
tell application "Finder"
	tell disk "$VOLUME"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set the bounds of container window to {200, 120, 860, 548}
		set viewOptions to the icon view options of container window
		set arrangement of viewOptions to not arranged
		set icon size of viewOptions to 104
		set text size of viewOptions to 13
		set background picture of viewOptions to file ".background:background.png"
		set position of item "$APP_NAME.app" of container window to {165, 205}
		set position of item "Applications" of container window to {495, 205}
		update without registering applications
		close
	end tell
end tell
EOF
then
  echo "warning: Finder layout step failed — the DMG will use Finder's default layout"
fi

sync
hdiutil detach "$DEVICE" >/dev/null
trap - EXIT

echo "Compressing…"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT_DMG" >/dev/null
rm -f "$RW_DMG" build/dmg-background.png
rm -rf "$STAGE"
codesign --force --sign - "$OUT_DMG"

# Stamp the app icon onto the .dmg file itself so it shows in Finder/Downloads
# instead of the generic disk-image icon. Done after codesign — the icon is a
# resource-fork xattr, not part of the signed image data. Non-fatal: if a
# headless runner can't set it, the DMG still installs fine.
echo "Setting DMG file icon…"
swift Scripts/SetFileIcon.swift "$OUT_DMG" "$APP/Contents/Resources/AppIcon.icns" \
  || echo "warning: could not set the DMG file icon — using Finder's default"

echo "Done → $PWD/$OUT_DMG"
