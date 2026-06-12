#!/usr/bin/env bash
# Build a Parallel.app bundle from the SwiftPM executable.
# Usage: ./scripts/build-app.sh [version]
set -euo pipefail

VERSION="${1:-0.1.0}"
APP_NAME="Parallel"
BUNDLE_ID="com.bottlepumpkin.parallel"
OUT_DIR="build"

cd "$(dirname "$0")/.."

echo "==> swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
[ -f "$BIN_PATH" ] || { echo "binary not found: $BIN_PATH"; exit 1; }

APP_DIR="$OUT_DIR/$APP_NAME.app"
rm -rf "$OUT_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc sign so macOS doesn't refuse to launch with "the app is damaged".
# Not a Developer ID signature — users still see "unidentified developer"
# the first time and need right-click → Open. But this avoids the harsher
# Gatekeeper rejection that happens when the .app has no signature at all.
echo "==> codesign (ad-hoc)"
codesign --force --deep --sign - "$APP_DIR"

ZIP_NAME="$APP_NAME-$VERSION-mac.zip"
# `ditto` preserves extended attributes and codesign metadata; plain `zip`
# strips them on some macOS versions which re-triggers the damaged-app
# error.
( cd "$OUT_DIR" && ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_NAME" )

echo
echo "==> Built:"
echo "    $OUT_DIR/$APP_NAME.app"
echo "    $OUT_DIR/$ZIP_NAME"
