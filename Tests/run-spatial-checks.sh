#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
: "${SDKROOT:=$(xcrun --sdk macosx --show-sdk-path)}"
export SDKROOT
BUKO_SPATIAL_DIR="$(mktemp -d /private/tmp/BukoSpatialChecks.XXXXXX)"
trap 'rm -rf "$BUKO_SPATIAL_DIR"' EXIT
python3 Tests/SpatialAutofill/prepare.py --destination "$BUKO_SPATIAL_DIR/source" --instrument-reader
xcrun swift build --package-path "$BUKO_SPATIAL_DIR/source" -c release --disable-sandbox
# PencilKit requires a real bundle identifier when creating drawings on macOS.
# Keep all generated sources and bundle metadata outside the repository.
mkdir -p "$BUKO_SPATIAL_DIR/Checks.app/Contents/MacOS"
cp "$BUKO_SPATIAL_DIR/source/.build/release/buko-spatial" "$BUKO_SPATIAL_DIR/Checks.app/Contents/MacOS/checks"
cat > "$BUKO_SPATIAL_DIR/Checks.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.buko.SpatialChecks</string><key>CFBundleExecutable</key><string>checks</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
if [ "$#" -eq 0 ]; then
    "$BUKO_SPATIAL_DIR/Checks.app/Contents/MacOS/checks" --self-check --output "$BUKO_SPATIAL_DIR/self.json"
    "$BUKO_SPATIAL_DIR/Checks.app/Contents/MacOS/checks" --ink-guards --output "$BUKO_SPATIAL_DIR/guards.json"
else
    "$BUKO_SPATIAL_DIR/Checks.app/Contents/MacOS/checks" "$@"
fi
