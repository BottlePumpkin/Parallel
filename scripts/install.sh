#!/usr/bin/env bash
# Parallel — one-line install for macOS.
#   curl -fsSL https://raw.githubusercontent.com/BottlePumpkin/Parallel/master/scripts/install.sh | bash
#
# Downloads the latest release zip, strips the quarantine attribute (so
# Gatekeeper doesn't complain about "unidentified developer"), and drops
# Parallel.app into /Applications.
set -euo pipefail

REPO="BottlePumpkin/Parallel"
APP_NAME="Parallel.app"
INSTALL_DIR="/Applications"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "✗ macOS only." >&2
    exit 1
fi

echo "==> Looking up the latest release of $REPO"
ASSET_URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*-mac\.zip"' \
    | head -1 \
    | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')

if [ -z "${ASSET_URL:-}" ]; then
    echo "✗ Couldn't find a *-mac.zip asset in the latest release." >&2
    exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"

echo "==> Downloading $(basename "$ASSET_URL")"
curl -fL --progress-bar -o parallel.zip "$ASSET_URL"

echo "==> Unzipping"
ditto -x -k parallel.zip .

if [ ! -d "$APP_NAME" ]; then
    echo "✗ Unexpected zip contents — $APP_NAME not found." >&2
    exit 1
fi

echo "==> Removing quarantine attribute"
xattr -dr com.apple.quarantine "$APP_NAME" 2>/dev/null || true

if [ -d "$INSTALL_DIR/$APP_NAME" ]; then
    echo "==> Replacing existing $INSTALL_DIR/$APP_NAME"
    rm -rf "$INSTALL_DIR/$APP_NAME"
fi

echo "==> Moving to $INSTALL_DIR"
mv "$APP_NAME" "$INSTALL_DIR/"

echo
echo "✓ Installed: $INSTALL_DIR/$APP_NAME"
echo "  Launch:    open '$INSTALL_DIR/$APP_NAME'"
