#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_NAME="Codex Limit Bar"
APP="$ROOT/dist/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/Resources/CodexLimitBar-Info.plist")
ARTIFACT_NAME="Codex-Limit-Bar-$VERSION"
ZIP="$ROOT/dist/$ARTIFACT_NAME.zip"
DMG="$ROOT/dist/$ARTIFACT_NAME.dmg"
STAGING="$ROOT/.build/release-dmg"

ARCHS="arm64 x86_64" "$ROOT/scripts/build-app.sh"

rm -f "$ZIP" "$DMG" "$ROOT/dist/SHA256SUMS.txt"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

cd "$ROOT/dist"
shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > SHA256SUMS.txt

printf '%s\n%s\n%s\n' "$DMG" "$ZIP" "$ROOT/dist/SHA256SUMS.txt"
