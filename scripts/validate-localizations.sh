#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

extract_keys() {
    sed -n 's/^"\([^"]*\)".*/\1/p' "$1" | sort
}

REFERENCE="$ROOT/Resources/en.lproj/Localizable.strings"
extract_keys "$REFERENCE" > "$TEMP_DIR/en.keys"

for LANGUAGE in en uk ru; do
    STRINGS="$ROOT/Resources/$LANGUAGE.lproj/Localizable.strings"
    plutil -lint "$STRINGS" >/dev/null
    extract_keys "$STRINGS" > "$TEMP_DIR/$LANGUAGE.keys"
    if ! diff -u "$TEMP_DIR/en.keys" "$TEMP_DIR/$LANGUAGE.keys"; then
        printf 'Localization keys differ for %s.\n' "$LANGUAGE" >&2
        exit 1
    fi
done

printf 'Localization validation passed for en, uk, and ru.\n'
