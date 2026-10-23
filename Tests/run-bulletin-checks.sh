#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
BUKO_BULLETIN_DIR="$(mktemp -d /private/tmp/BukoBulletinChecks.XXXXXX)"
trap 'rm -rf "$BUKO_BULLETIN_DIR"' EXIT
BUKO_BULLETIN_MAIN="Tests/BulletinLibraryChecks.swift"
if [[ "${1:-}" == "--live" ]]; then BUKO_BULLETIN_MAIN="Tests/BulletinModelChecks.swift"; fi
if [[ "${1:-}" != "--live" ]]; then
    mkdir -p "$BUKO_BULLETIN_DIR/Legacy.app/Contents/MacOS"
    cat > "$BUKO_BULLETIN_DIR/Legacy.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.buko.BulletinLegacy</string><key>CFBundleExecutable</key><string>legacy</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
    xcrun swiftc -module-cache-path "$BUKO_BULLETIN_DIR/modules" -parse-as-library Tests/Fixtures/LegacyNotebook.swift -o "$BUKO_BULLETIN_DIR/Legacy.app/Contents/MacOS/legacy"
    "$BUKO_BULLETIN_DIR/Legacy.app/Contents/MacOS/legacy" "$BUKO_BULLETIN_DIR/legacy.store"
fi
mkdir -p "$BUKO_BULLETIN_DIR/Checks.app/Contents/MacOS"
cat > "$BUKO_BULLETIN_DIR/Checks.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.buko.BulletinChecks</string><key>CFBundleExecutable</key><string>checks</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -module-cache-path "$BUKO_BULLETIN_DIR/modules" \
    Buko/Models/Note.swift Buko/Models/NoteFolder.swift Buko/Models/TrashedPage.swift Buko/Models/NotebookEdits.swift \
    Buko/Models/BulletinItem.swift Buko/Canvas/PageGeometry.swift Buko/Canvas/NotebookPaging.swift \
    Buko/Bulletin/BandGeometry.swift Buko/Bulletin/BulletinExtractor.swift Buko/Bulletin/BulletinDateInterpreter.swift \
    Buko/Retrieval/LectureGroundingPolicy.swift Buko/Retrieval/LectureRetrieval.swift \
    Buko/Retrieval/GapRetrieval.swift Buko/AI/MissingInformationPlan.swift Buko/AI/IntentPrompts.swift \
    "$BUKO_BULLETIN_MAIN" -o "$BUKO_BULLETIN_DIR/Checks.app/Contents/MacOS/checks"
"$BUKO_BULLETIN_DIR/Checks.app/Contents/MacOS/checks" "$BUKO_BULLETIN_DIR/data" "$BUKO_BULLETIN_DIR/legacy.store"
