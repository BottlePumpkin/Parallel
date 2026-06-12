#!/usr/bin/env bash
# Build a Parallel.app bundle from the SwiftPM executable.
#
# Usage:
#   ./scripts/build-app.sh [version]
#
# Without env vars: ad-hoc signed build. Users still need right-click → Open.
#
# With Developer ID env vars: properly signed + notarized + stapled build
# that opens with a normal double-click on any Mac. Set once in your shell:
#
#   export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   export NOTARY_PROFILE="parallel-notary"   # see README setup steps
#
# `NOTARY_PROFILE` is a keychain profile created with:
#   xcrun notarytool store-credentials parallel-notary \
#       --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PW
set -euo pipefail

VERSION="${1:-0.1.0}"
APP_NAME="Parallel"
BUNDLE_ID="com.bottlepumpkin.parallel"
OUT_DIR="build"
ENTITLEMENTS="scripts/parallel.entitlements"

cd "$(dirname "$0")/.."

echo "==> swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
[ -f "$BIN_PATH" ] || { echo "binary not found: $BIN_PATH"; exit 1; }

APP_DIR="$OUT_DIR/$APP_NAME.app"
rm -rf "$OUT_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

ICON_PLIST=""
if [ -f "assets/AppIcon.icns" ]; then
    cp "assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
    ICON_PLIST="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
fi

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
$ICON_PLIST
</dict>
</plist>
EOF

if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "==> codesign with Developer ID + Hardened Runtime"
    codesign --force --deep \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        --timestamp \
        "$APP_DIR"
else
    echo "==> codesign (ad-hoc — not notarizable)"
    codesign --force --deep --sign - "$APP_DIR"
fi

ZIP_NAME="$APP_NAME-$VERSION-mac.zip"
make_zip() {
    rm -f "$OUT_DIR/$ZIP_NAME"
    ( cd "$OUT_DIR" && ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_NAME" )
}
echo "==> ditto -c -k (first pass)"
make_zip

if [ -n "${NOTARY_PROFILE:-}" ] && [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "==> notarytool submit --wait (typically 1-5 minutes)"
    xcrun notarytool submit "$OUT_DIR/$ZIP_NAME" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "==> stapler staple"
    xcrun stapler staple "$APP_DIR"

    echo "==> ditto -c -k (re-zip with stapled ticket)"
    make_zip

    echo "==> verifying notarization"
    spctl -a -vvv -t install "$APP_DIR" || true
fi

echo
echo "==> Built:"
echo "    $OUT_DIR/$APP_NAME.app"
echo "    $OUT_DIR/$ZIP_NAME"
