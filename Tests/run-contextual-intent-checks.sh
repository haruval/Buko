#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUKO_CONTEXT_DIR="$(mktemp -d /private/tmp/BukoContextChecks.XXXXXX)"
trap 'rm -rf "$BUKO_CONTEXT_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUKO_CONTEXT_DIR/modules" \
    Buko/AI/PipelineDiagnostics.swift Buko/AI/IntentPrompts.swift Buko/AI/MissingInformationPlan.swift Buko/AI/CirclePlanner.swift \
    Buko/AI/AutofillProposal.swift Buko/AI/AutofillWriter.swift \
    Buko/Retrieval/GapRetrieval.swift Buko/Retrieval/LectureRetrieval.swift \
    Buko/Retrieval/LectureGroundingPolicy.swift Buko/Retrieval/LectureComposer.swift \
    Buko/Retrieval/LectureLibrary.swift Buko/Retrieval/LecturePageExtractor.swift \
    Tests/ContextualIntentChecks.swift -o "$BUKO_CONTEXT_DIR/checks"
"$BUKO_CONTEXT_DIR/checks" "$@"
