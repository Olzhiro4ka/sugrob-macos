#!/usr/bin/env bash
# Assembles build/Sugrob.app from the SwiftPM build and ad-hoc signs it.
#
# Usage: scripts/bundle.sh [debug|release] [--universal]
#   debug        (default) native-arch debug build, used by `make run`
#   release      native-arch release build
#   --universal  release only: arm64 + x86_64 merged with lipo
#
# Env: VERSION (default: latest v* tag or 0.0.0), BUNDLE_ID, SIGN_IDENTITY (default "-" = ad-hoc).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
UNIVERSAL=0
[[ "${2:-}" == "--universal" ]] && UNIVERSAL=1

APP_NAME="Sugrob"
BUNDLE_ID="${BUNDLE_ID:-io.github.olzhiro4ka.sugrob}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
  VERSION="${VERSION#v}"
  VERSION="${VERSION:-0.0.0}"
fi
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

APP="build/${APP_NAME}.app"
SWIFT_FLAGS=(-c "$CONFIG" -Xswiftc -warnings-as-errors)

if [[ "$UNIVERSAL" == 1 ]]; then
  [[ "$CONFIG" == "release" ]] || { echo "--universal requires release" >&2; exit 1; }
  for arch in arm64 x86_64; do
    swift build "${SWIFT_FLAGS[@]}" --arch "$arch"
  done
  BIN_ARM="$(swift build "${SWIFT_FLAGS[@]}" --arch arm64 --show-bin-path)/${APP_NAME}"
  BIN_X86="$(swift build "${SWIFT_FLAGS[@]}" --arch x86_64 --show-bin-path)/${APP_NAME}"
else
  swift build "${SWIFT_FLAGS[@]}"
  BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)/${APP_NAME}"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "$UNIVERSAL" == 1 ]]; then
  lipo -create -output "$APP/Contents/MacOS/${APP_NAME}" "$BIN_ARM" "$BIN_X86"
else
  cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"
fi

sed -e "s/__BUNDLE_ID__/${BUNDLE_ID}/" \
    -e "s/__VERSION__/${VERSION}/" \
    -e "s/__BUILD__/${BUILD_NUMBER}/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"

if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  plutil -replace CFBundleIconFile -string AppIcon "$APP/Contents/Info.plist"
fi
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Resources/SnowplowVariant2.png "$APP/Contents/Resources/SnowplowVariant2.png"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --timestamp=none "$APP"
else
  # Developer ID: hardened runtime and a secure timestamp are required for notarization.
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP"
fi
codesign --verify --strict "$APP"

echo "Built $APP (version $VERSION, build $BUILD_NUMBER, $CONFIG$([[ $UNIVERSAL == 1 ]] && echo ', universal'))"
