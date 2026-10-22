#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUKO_GAP_CHECK="$(mktemp -d /private/tmp/BukoGapChecks.XXXXXX)"
trap 'rm -rf "$BUKO_GAP_CHECK"' EXIT
xcrun swiftc -module-cache-path "$BUKO_GAP_CHECK/modules" \
    Buko/AI/IntentPrompts.swift Buko/AI/MissingInformationPlan.swift \
    Buko/Retrieval/LectureRetrieval.swift Buko/Retrieval/GapRetrieval.swift \
    Buko/Retrieval/LectureGroundingPolicy.swift Buko/Retrieval/LectureLibrary.swift Buko/Retrieval/LecturePageExtractor.swift \
    Tests/LectureEvidenceFixtures.swift Tests/GapBenchmarkSupport.swift Tests/MissingInformationChecks.swift -o "$BUKO_GAP_CHECK/checks"
"$BUKO_GAP_CHECK/checks"
