#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
BUKO_LIBRARY_DIR="$(mktemp -d /private/tmp/BukoLibraryChecks.XXXXXX)"
trap 'rm -rf "$BUKO_LIBRARY_DIR"' EXIT
mkdir -p "$BUKO_LIBRARY_DIR/Legacy.app/Contents/MacOS"
cat > "$BUKO_LIBRARY_DIR/Legacy.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.buko.LibraryLegacy</string><key>CFBundleExecutable</key><string>legacy</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -module-cache-path "$BUKO_LIBRARY_DIR/modules" -parse-as-library Tests/Fixtures/LegacyNotebook.swift -o "$BUKO_LIBRARY_DIR/Legacy.app/Contents/MacOS/legacy"
"$BUKO_LIBRARY_DIR/Legacy.app/Contents/MacOS/legacy" "$BUKO_LIBRARY_DIR/legacy.store"
mkdir -p "$BUKO_LIBRARY_DIR/Checks.app/Contents/MacOS"
cat > "$BUKO_LIBRARY_DIR/Checks.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.buko.LibraryChecks</string><key>CFBundleExecutable</key><string>checks</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
# This frozen synthetic store exercises opening the previous shipping schema.
gunzip -c Tests/Fixtures/PreRemovalLibrary.store.gz > "$BUKO_LIBRARY_DIR/retired.store"
BUKO_LIBRARY_SOURCES=(Buko/Models/Note.swift Buko/Models/NoteFolder.swift Buko/Models/TrashedPage.swift
        Buko/Models/NotebookEdits.swift Buko/Canvas/PageGeometry.swift Buko/Canvas/NotebookPaging.swift)
xcrun swiftc -module-cache-path "$BUKO_LIBRARY_DIR/modules" "${BUKO_LIBRARY_SOURCES[@]}" \
    Tests/LibraryOrganizationChecks.swift \
    -o "$BUKO_LIBRARY_DIR/Checks.app/Contents/MacOS/checks"
"$BUKO_LIBRARY_DIR/Checks.app/Contents/MacOS/checks" "$BUKO_LIBRARY_DIR/data" "$BUKO_LIBRARY_DIR/legacy.store" "$BUKO_LIBRARY_DIR/retired.store"
