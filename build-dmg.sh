#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:a:h}
APP_NAME="Hibernate Control"
VERSION=$(cat "$SCRIPT_DIR/VERSION")
DMG_NAME="$APP_NAME-$VERSION.dmg"
STAGING_DIR="$SCRIPT_DIR/build/dmg-staging"
DMG_PATH="$SCRIPT_DIR/releases/$DMG_NAME"
APP_BUNDLE="$SCRIPT_DIR/dist/$APP_NAME.app"

"$SCRIPT_DIR/build-app.sh"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "Created $DMG_PATH"
echo "Open with: open \"$DMG_PATH\""