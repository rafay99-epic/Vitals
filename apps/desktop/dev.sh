#!/bin/zsh
# Builds the CURRENT branch as the Dev channel and installs it next to Stable.
# Stable (/Applications/Vitals.app) is never touched — break Dev all you like.
# Usage: ./dev.sh
set -euo pipefail
cd "$(dirname "$0")"

VITALS_CHANNEL=dev ./build.sh

APP="build/Vitals Dev.app"
DEST="/Applications/Vitals Dev.app"

echo "Installing → $DEST"
osascript -e 'tell application "Vitals Dev" to quit' 2>/dev/null || true
sleep 1
rm -rf "$DEST"
ditto "$APP" "$DEST"
open "$DEST"
echo "Launched Vitals Dev — branch $(git rev-parse --abbrev-ref HEAD 2>/dev/null) @ $(git rev-parse --short HEAD 2>/dev/null)"
