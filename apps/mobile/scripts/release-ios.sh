#!/usr/bin/env bash
# Builds the iPhone app and uploads it to App Store Connect: Stable from `main` (TestFlight, then the
# App Store), Nightly from `nightly` (TestFlight only). JS-only changes don't need this:
# `pnpm update:stable` / `update:nightly` send them over the air.
#
# Usage: release-ios.sh <stable|nightly> [--archive-only]
# --archive-only builds and checks the archive from any branch and uploads nothing.
#
# Needs: Xcode signed in to the Syntax Labs team, which signs automatically and registers the app ids,
# App Group and profiles on the first run; the built-in Tailscale libs
# (packages/tailnet/scripts/build-native.sh); and, to upload, the app's record in App Store Connect.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "release-ios: $*" >&2; exit 1; }

TEAM=MGH5K382YN
variant="${1:-}"
case "$variant" in
  stable) branch=main suffix="" channel=production ;;
  nightly) branch=nightly suffix=".nightly" channel=nightly ;;
  *) fail "usage: release-ios.sh <stable|nightly> [--archive-only]" ;;
esac
upload=true
[ "${2:-}" = --archive-only ] && upload=false

[ -d ../../packages/tailnet/ios/Tailnet.xcframework ] || fail "build the Tailscale libs first: packages/tailnet/scripts/build-native.sh"
if $upload; then
  [ "$(git rev-parse --abbrev-ref HEAD)" = "$branch" ] || fail "run this from the $branch branch"
  git diff --quiet HEAD -- . ../../packages || fail "commit or stash your app changes first"
  git fetch -q origin "$branch"
  [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$branch")" ] || fail "local $branch does not match origin/$branch"
fi

build=$(git rev-list --count HEAD)
export APP_VARIANT="$variant"
SENTRY_AUTH_TOKEN="$(../../scripts/with-sentry.sh sh -c 'printf %s "${SENTRY_AUTH_TOKEN:-}"')"
if [ -n "$SENTRY_AUTH_TOKEN" ]; then export SENTRY_AUTH_TOKEN; else export SENTRY_DISABLE_AUTO_UPLOAD=true; fi

npx expo prebuild --clean --platform ios
workspace=$(cd ios && ls -d ./*.xcworkspace | head -1)
[ -n "$workspace" ] || fail "prebuild made no .xcworkspace"
scheme=$(basename "$workspace" .xcworkspace)
archive="ios/build/$scheme.xcarchive"

# The team goes on the command line, not in app.config.ts: a config change would move the runtime
# fingerprint and cut installed apps off quick updates.
xcodebuild -workspace "ios/$scheme.xcworkspace" -scheme "$scheme" -configuration Release \
  -destination generic/platform=iOS -archivePath "$archive" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" -quiet archive

# Check the archive is the app we meant to ship before it leaves the Mac.
app="$archive/Products/Applications/$scheme.app"
got_id=$(plutil -extract CFBundleIdentifier raw "$app/Info.plist")
got_build=$(plutil -extract CFBundleVersion raw "$app/Info.plist")
got_channel=$(jq -r '.updates.requestHeaders["expo-channel-name"]' "$app/EXConstants.bundle/app.config")
[ "$got_id" = "com.syntaxlabtechnology.vitals.remote$suffix" ] || fail "archive has bundle id $got_id"
[ "$got_build" = "$build" ] || fail "archive has build $got_build, expected $build"
[ "$got_channel" = "$channel" ] || fail "archive reads updates from channel $got_channel, expected $channel"
echo "release-ios: archived $got_id build $build (channel $channel)"

$upload || { echo "release-ios: --archive-only, nothing uploaded ($archive)"; exit 0; }

options="$(mktemp -d)/ExportOptions.plist"
cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
<key>teamID</key><string>$TEAM</string>
<key>signingStyle</key><string>automatic</string>
<key>manageAppVersionAndBuildNumber</key><false/>
<key>uploadSymbols</key><true/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" \
  -exportPath ios/build/export -allowProvisioningUpdates

echo "release-ios: uploaded build $build. It reaches TestFlight once Apple finishes processing it."
