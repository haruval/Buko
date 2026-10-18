#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUKO_GROUNDING_DIR="$(mktemp -d /private/tmp/BukoGrounding.XXXXXX)"
trap 'rm -rf "$BUKO_GROUNDING_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUKO_GROUNDING_DIR/modules" \
    Buko/Retrieval/LectureRetrieval.swift Buko/Retrieval/LectureLibrary.swift Buko/Retrieval/LecturePageExtractor.swift \
    Buko/Retrieval/LectureGroundingPolicy.swift Buko/Retrieval/LectureComposer.swift Buko/AI/IntentPrompts.swift \
    Buko/AI/MatrixProductCheck.swift Buko/AI/CircleCompletionRoute.swift \
    Tests/LectureGroundingChecks.swift -o "$BUKO_GROUNDING_DIR/checks"
"$BUKO_GROUNDING_DIR/checks" "$BUKO_GROUNDING_DIR/library" "$PWD/Buko/Resources/Lectures"
