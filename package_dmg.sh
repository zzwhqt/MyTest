#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Info.plist")"
APP_PATH="$PROJECT_DIR/dist/轻刷题.app"
DMG_PATH="$PROJECT_DIR/dist/轻刷题-${VERSION}-macOS.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quickquiz-dmg.XXXXXX")"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

"$PROJECT_DIR/build.sh"

ditto "$APP_PATH" "$STAGING_DIR/轻刷题.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "轻刷题" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

hdiutil verify "$DMG_PATH"
echo "$DMG_PATH"
