#!/usr/bin/env bash
# Packs build/Sugrob.app into build/Sugrob-<version>.zip and build/Sugrob-<version>.dmg
# for GitHub Releases. The dmg holds the app and an /Applications link for drag-to-install.
#
# Env: SIGN_IDENTITY (default "-"): when it is a real identity, the dmg is signed too.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Sugrob.app"
[[ -d "$APP" ]] || { echo "$APP missing; run make app" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="build/Sugrob-${VERSION}.zip"
DMG="build/Sugrob-${VERSION}.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Sugrob.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "Sugrob" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

(cd build && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > "Sugrob-${VERSION}.sha256")
echo "Built $ZIP and $DMG"
cat "build/Sugrob-${VERSION}.sha256"
