#!/usr/bin/env bash
# Builds the Nightly Android app from `nightly` and publishes it as the rolling `android-nightly`
# pre-release, which installed Nightly apps check for new builds (src/lib/nightly.ts).
# JS-only changes don't need this: `pnpm update:nightly` sends them over the air.
#
# Needs: the Android SDK, the built-in Tailscale native libs (packages/tailnet/scripts/build-native.sh),
# the upload key in ~/.gradle/gradle.properties (VITALS_UPLOAD_*), and `gh` signed in.
# Every Nightly APK must be signed with that same key, or Android refuses to update over it.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "release-nightly: $*" >&2; exit 1; }

[ "$(git rev-parse --abbrev-ref HEAD)" = nightly ] || fail "run this from the nightly branch"
git diff --quiet HEAD -- . ../../packages || fail "commit or stash your app changes first"
git fetch -q origin nightly
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/nightly)" ] || fail "local nightly does not match origin/nightly"
grep -q '^VITALS_UPLOAD_STORE_FILE=' "$HOME/.gradle/gradle.properties" 2>/dev/null || fail "no upload key in ~/.gradle/gradle.properties"

build=$(git rev-list --count HEAD)
export APP_VARIANT=nightly ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
SENTRY_AUTH_TOKEN="$(../../scripts/with-sentry.sh sh -c 'printf %s "${SENTRY_AUTH_TOKEN:-}"')"
if [ -n "$SENTRY_AUTH_TOKEN" ]; then export SENTRY_AUTH_TOKEN; else export SENTRY_DISABLE_AUTO_UPLOAD=true; fi

# --clean regenerates android/, which also drops Gradle's cached JS bundle.
npx expo prebuild --clean --platform android --no-install
# The Tailscale libs ship for these two ABIs only.
(cd android && ./gradlew assembleRelease -PreactNativeArchitectures=arm64-v8a,x86_64)

apk="$(mktemp -d)/Vitals-Nightly.apk"
cp android/app/build/outputs/apk/release/app-release.apk "$apk"

gh release delete android-nightly --yes --cleanup-tag 2>/dev/null || true
gh release create android-nightly "$apk" \
  --prerelease \
  --target "$(git rev-parse HEAD)" \
  --title "Vitals Nightly for Android · build $build" \
  --notes "The Nightly beta of the phone app, built from \`nightly\` at $(git rev-parse --short HEAD). Install it next to the store app; it updates itself from here."

echo "release-nightly: published build $build"
