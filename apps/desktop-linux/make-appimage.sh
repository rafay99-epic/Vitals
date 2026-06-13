#!/usr/bin/env bash
# Builds Vitals-x86_64.AppImage — a single-file, no-install bundle of the Linux
# app plus its GTK4/libadwaita runtime. Run on Linux with the dev packages, plus
# curl, librsvg2-bin, patchelf, and desktop-file-utils. Matches CI.
set -euo pipefail
cd "$(dirname "$0")"

APPID="com.rafay99.Vitals"
COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
export VITALS_VERSION="${VITALS_VERSION:-0.$COMMIT_COUNT}"

# 1. Compile the release binary.
./build.sh

# 2. Lay out the AppDir.
APPDIR="AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" \
         "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp build/Vitals "$APPDIR/usr/bin/Vitals"
cp "packaging/$APPID.desktop" "$APPDIR/usr/share/applications/$APPID.desktop"
# Render the icon from SVG (librsvg) — no binary blobs in the repo.
rsvg-convert -w 256 -h 256 "packaging/icon.svg" \
  -o "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APPID.png"

# 3. Fetch linuxdeploy + its GTK plugin (bundles GTK4/libadwaita runtime: the
#    binary's NEEDED libs, gdk-pixbuf loaders, GSettings schemas, icon theme).
TOOLS=".tools"
mkdir -p "$TOOLS"
fetch() { [ -f "$TOOLS/$1" ] || curl -fL -o "$TOOLS/$1" "$2"; chmod +x "$TOOLS/$1"; }
fetch linuxdeploy-x86_64.AppImage \
  "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
fetch linuxdeploy-plugin-gtk.sh \
  "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh"

# 4. Build the AppImage. EXTRACT_AND_RUN avoids needing FUSE (e.g. in CI
#    containers); DEPLOY_GTK_VERSION targets the GTK4 runtime.
export PATH="$PWD/$TOOLS:$PATH"
export APPIMAGE_EXTRACT_AND_RUN=1
export DEPLOY_GTK_VERSION=4
export OUTPUT="Vitals-x86_64.AppImage"

"$TOOLS/linuxdeploy-x86_64.AppImage" \
  --appdir "$APPDIR" \
  --plugin gtk \
  --desktop-file "$APPDIR/usr/share/applications/$APPID.desktop" \
  --icon-file "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APPID.png" \
  --output appimage

mkdir -p build
mv -f "$OUTPUT" "build/$OUTPUT"
echo "Done → $PWD/build/$OUTPUT ($VITALS_VERSION)"
