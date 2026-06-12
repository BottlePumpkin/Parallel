#!/usr/bin/env bash
# Build an Apple .icns from a single square PNG.
# Usage: ./scripts/make-icns.sh [source.png] [output.icns]
set -euo pipefail

SRC="${1:-assets/icon-source.png}"
DST="${2:-assets/AppIcon.icns}"

cd "$(dirname "$0")/.."

[ -f "$SRC" ] || { echo "✗ source not found: $SRC" >&2; exit 1; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
ICONSET="$TMPDIR/icon.iconset"
mkdir -p "$ICONSET"

# Apple's expected names + sizes for an iconset.
declare -a SIZES=(
    "16   icon_16x16.png"
    "32   icon_16x16@2x.png"
    "32   icon_32x32.png"
    "64   icon_32x32@2x.png"
    "128  icon_128x128.png"
    "256  icon_128x128@2x.png"
    "256  icon_256x256.png"
    "512  icon_256x256@2x.png"
    "512  icon_512x512.png"
    "1024 icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
    SIZE="${entry%% *}"
    NAME="${entry##* }"
    sips -z "$SIZE" "$SIZE" "$SRC" --out "$ICONSET/$NAME" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$DST"
echo "✓ Built $DST"
