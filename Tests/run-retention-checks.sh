#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUKO_RETENTION_DIR="$(mktemp -d /private/tmp/BukoRetentionChecks.XXXXXX)"
trap 'rm -rf "$BUKO_RETENTION_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUKO_RETENTION_DIR/modules" \
    Buko/Models/Note.swift Buko/Models/TrashedPage.swift Buko/Models/NotebookEdits.swift \
    Buko/Canvas/PageGeometry.swift Buko/Canvas/NotebookPaging.swift \
    Buko/AI/IntentPrompts.swift Buko/AI/MissingInformationPlan.swift \
    Buko/Retrieval/LectureGroundingPolicy.swift Buko/Retrieval/GapRetrieval.swift \
    Buko/Retrieval/LectureRetrieval.swift Buko/Retrieval/LectureLibrary.swift Buko/Retrieval/LecturePageExtractor.swift \
    Tests/RetentionChecks.swift -o "$BUKO_RETENTION_DIR/checks"
"$BUKO_RETENTION_DIR/checks" "$BUKO_RETENTION_DIR" "$PWD/Buko/Resources/Lectures/programmingLanguages.pdf"
