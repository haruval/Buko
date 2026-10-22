#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUKO_SELECTION_DIR="$(mktemp -d /private/tmp/BukoEvidenceSelection.XXXXXX)"
trap 'rm -rf "$BUKO_SELECTION_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUKO_SELECTION_DIR/modules" \
    Buko/AI/IntentPrompts.swift Buko/AI/MissingInformationPlan.swift Buko/Retrieval/GapRetrieval.swift \
    Buko/Retrieval/LectureRetrieval.swift Buko/Retrieval/LectureGroundingPolicy.swift \
    Buko/Retrieval/LectureComposer.swift Tests/LectureEvidenceSelectionChecks.swift \
    -o "$BUKO_SELECTION_DIR/checks"
"$BUKO_SELECTION_DIR/checks" "$@"
