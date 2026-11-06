#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUKO_INSERTION_DIR="$(mktemp -d /private/tmp/BukoInsertionChecks.XXXXXX)"
trap 'rm -rf "$BUKO_INSERTION_DIR"' EXIT
mkdir -p "$BUKO_INSERTION_DIR/Checks.app/Contents/MacOS"
cat > "$BUKO_INSERTION_DIR/Checks.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.buko.InsertionChecks</string><key>CFBundleExecutable</key><string>checks</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -module-cache-path "$BUKO_INSERTION_DIR/modules" \
    Buko/Canvas/PageGeometry.swift Buko/Canvas/NotebookPaging.swift Buko/Canvas/MonochromeInk.swift \
    Buko/Models/Note.swift Buko/Models/TrashedPage.swift Buko/Models/NotebookEdits.swift \
    Buko/AI/CircleGeometry.swift Buko/AI/HandwritingSamples.swift Buko/AI/HandwrittenFont.swift \
    Buko/AI/AutofillTypography.swift Buko/AI/HandwritingSampler.swift Buko/AI/HandwritingPreparation.swift Buko/Development/LectureHandwriting.swift Buko/AI/AutofillLayout.swift \
    Buko/AI/AutofillDocument.swift Buko/AI/AutofillProposal.swift Buko/AI/AutofillInsertionState.swift \
    Buko/AI/IntentPrompts.swift Buko/AI/MissingInformationPlan.swift \
    Buko/Retrieval/GapRetrieval.swift Buko/Retrieval/LectureRetrieval.swift Buko/Retrieval/LectureGroundingPolicy.swift \
    Buko/Retrieval/LectureLibrary.swift Buko/Retrieval/LecturePageExtractor.swift \
    Buko/AI/AutofillReflowSpring.swift Tests/AutofillReflowChecks.swift \
    Tests/PreparedHandwritingChecks.swift Tests/AutofillPreparationRaceChecks.swift Tests/AutofillInsertionChecks.swift -o "$BUKO_INSERTION_DIR/Checks.app/Contents/MacOS/checks"
"$BUKO_INSERTION_DIR/Checks.app/Contents/MacOS/checks" "$BUKO_INSERTION_DIR/data"
