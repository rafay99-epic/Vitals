#!/usr/bin/env bash
# Builds the Vitals Linux binary. Run on Linux (or inside the Dockerfile image);
# it needs gtk4 + libadwaita + cairo dev packages present. Usage: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

# Version is 0.<total commit count>, matching the macOS app. CI passes
# VITALS_VERSION; local builds compute it from the repo. This is for display
# only — the Linux app ships no updater, so the number never gates anything.
COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
export VITALS_VERSION="${VITALS_VERSION:-0.$COMMIT_COUNT}"
echo "Building Vitals (Linux) $VITALS_VERSION…"

swift build -c release
BINARY=".build/release/Vitals"

rm -rf build
mkdir -p build
cp "$BINARY" build/Vitals
echo "Done → $PWD/build/Vitals ($VITALS_VERSION)"
