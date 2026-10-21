#!/usr/bin/env bash
# Builds the embedded Tailscale node (tsnet) into the native libraries the Expo
# module links: android/libs/tailnet.aar and ios/Tailnet.xcframework.
# Needs Go, gomobile (go install golang.org/x/mobile/cmd/gomobile@latest) and the Android NDK.
set -euo pipefail
cd "$(dirname "$0")/../go"
export PATH="$PATH:$(go env GOPATH)/bin"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$(ls -d "$ANDROID_HOME"/ndk/* | sort -V | tail -1)}"
gomobile init
mkdir -p ../android/libs
gomobile bind -target=android/arm64,android/amd64 -androidapi 24 -ldflags="-s -w" -javapkg dev.vitals -o ../android/libs/tailnet.aar .
# A library module can't depend on a local .aar, so unpack it into a jar and jniLibs.
rm -rf ../android/src/main/jniLibs && mkdir -p ../android/src/main/jniLibs
unzip -o -q ../android/libs/tailnet.aar classes.jar -d ../android/libs && mv ../android/libs/classes.jar ../android/libs/tailnet.jar
unzip -o -q ../android/libs/tailnet.aar 'jni/*' -d ../android/libs/unpacked && cp -R ../android/libs/unpacked/jni/. ../android/src/main/jniLibs/
rm -rf ../android/libs/unpacked ../android/libs/tailnet.aar
if [[ "$(uname)" == "Darwin" ]]; then
  gomobile bind -target=ios,iossimulator -ldflags="-s -w" -o ../ios/Tailnet.xcframework .
fi
