#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_NAME="Codex Limit Bar"
APP="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP/Contents"
PLIST="$ROOT/Resources/CodexLimitBar-Info.plist"
ARCHS=${ARCHS:-"$(uname -m)"}
BINARY_STAGING="$ROOT/.build/release-binaries"

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/swiftpm-module-cache"

mkdir -p "$ROOT/dist"
rm -rf "$APP"
rm -rf "$BINARY_STAGING"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
mkdir -p "$BINARY_STAGING"

for ARCH in $ARCHS; do
    BUILD_PATH="$ROOT/.build/$ARCH"
    TRIPLE="$ARCH-apple-macosx13.0"
    swift build \
        --package-path "$ROOT" \
        --scratch-path "$BUILD_PATH" \
        --triple "$TRIPLE" \
        --disable-sandbox \
        -c release \
        --product codex-limit-bar
    BIN_DIR=$(swift build \
        --package-path "$ROOT" \
        --scratch-path "$BUILD_PATH" \
        --triple "$TRIPLE" \
        --disable-sandbox \
        -c release \
        --show-bin-path)
    cp "$BIN_DIR/codex-limit-bar" "$BINARY_STAGING/$ARCH"
done

set -- $ARCHS
if [ "$#" -eq 1 ]; then
    cp "$BINARY_STAGING/$1" "$CONTENTS/MacOS/CodexLimitBar"
elif [ "$#" -eq 2 ]; then
    xcrun lipo -create \
        "$BINARY_STAGING/$1" \
        "$BINARY_STAGING/$2" \
        -output "$CONTENTS/MacOS/CodexLimitBar"
else
    printf 'Expected one or two architectures, received: %s\n' "$ARCHS" >&2
    exit 1
fi

cp "$PLIST" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

SIGN_IDENTITY=${CODE_SIGN_IDENTITY:--}
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP" >/dev/null
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"
