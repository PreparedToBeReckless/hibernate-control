#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:a:h}
APP_NAME="Hibernate Control"
BUILD_DIR="$SCRIPT_DIR/build"
DIST_DIR="$SCRIPT_DIR/dist"
RELEASES_DIR="$SCRIPT_DIR/releases"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
SOURCES_DIR="$SCRIPT_DIR/Sources/HibernateControl"
VERSION=$(cat "$SCRIPT_DIR/VERSION")

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR/$APP_NAME.app/Contents/MacOS" "$DIST_DIR/$APP_NAME.app/Contents/Resources" "$RELEASES_DIR"

SDK=$(xcrun --show-sdk-path)
swiftc -O \
  -sdk "$SDK" \
  -target "$(uname -m)-apple-macos13.0" \
  -o "$BUILD_DIR/HibernateControl" \
  "$SOURCES_DIR"/*.swift \
  -framework AppKit \
  -framework Carbon \
  -framework ServiceManagement \
  -framework SwiftUI

cp "$BUILD_DIR/HibernateControl" "$APP_BUNDLE/Contents/MacOS/HibernateControl"
chmod +x "$APP_BUNDLE/Contents/MacOS/HibernateControl"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>HibernateControl</string>
    <key>CFBundleIdentifier</key>
    <string>com.hibernatecontrol.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Hibernate Control</string>
</dict>
</plist>
EOF

ARCHIVE_PATH="$RELEASES_DIR/$APP_NAME-$VERSION.app"
rm -rf "$ARCHIVE_PATH"
cp -R "$APP_BUNDLE" "$ARCHIVE_PATH"

echo "Built $APP_BUNDLE"
echo "Archived $ARCHIVE_PATH"
echo "Open with: open \"$APP_BUNDLE\""