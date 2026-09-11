#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUKO_CHECK_DIR="$(mktemp -d /private/tmp/BukoChecks.XXXXXX)"
trap 'rm -rf "$BUKO_CHECK_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUKO_CHECK_DIR/modules" \
    Buko/Canvas/PageGeometry.swift Tests/PageGeometryChecks.swift \
    -o "$BUKO_CHECK_DIR/geometry"
"$BUKO_CHECK_DIR/geometry"
xcrun swiftc -module-cache-path "$BUKO_CHECK_DIR/modules" \
    Buko/Models/Note.swift Tests/NoteStorageChecks.swift \
    -o "$BUKO_CHECK_DIR/storage"
"$BUKO_CHECK_DIR/storage"
mkdir -p "$BUKO_CHECK_DIR/InkChecks.app/Contents/MacOS"
cat > "$BUKO_CHECK_DIR/InkChecks.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.buko.InkChecks</string><key>CFBundleExecutable</key><string>ink</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -module-cache-path "$BUKO_CHECK_DIR/modules" \
    Buko/Canvas/MonochromeInk.swift Tests/MonochromeInkChecks.swift \
    -o "$BUKO_CHECK_DIR/InkChecks.app/Contents/MacOS/ink"
"$BUKO_CHECK_DIR/InkChecks.app/Contents/MacOS/ink"
xcrun swiftc -module-cache-path "$BUKO_CHECK_DIR/modules" \
    Buko/Canvas/PageGeometry.swift Buko/Canvas/NotebookPaging.swift Tests/NotebookPagingChecks.swift \
    -o "$BUKO_CHECK_DIR/paging"
"$BUKO_CHECK_DIR/paging"
