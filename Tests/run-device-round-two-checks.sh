#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUKO_AUTOFILL_DIR="$(mktemp -d /private/tmp/BukoAutofillChecks.XXXXXX)"
printf 'Evidence directory: %s\n' "$BUKO_AUTOFILL_DIR"
xcrun swiftc -module-cache-path "$BUKO_AUTOFILL_DIR/modules" \
    Buko/AI/PipelineDiagnostics.swift Buko/AI/IntentPrompts.swift Buko/AI/MissingInformationPlan.swift Buko/AI/CirclePlanner.swift \
    Buko/AI/AutofillProposal.swift Buko/AI/AutofillWriter.swift \
    Buko/Retrieval/GapRetrieval.swift Buko/Retrieval/LectureRetrieval.swift \
    Buko/Retrieval/LectureGroundingPolicy.swift Buko/Retrieval/LectureComposer.swift \
    Buko/Retrieval/LectureLibrary.swift Buko/Retrieval/LecturePageExtractor.swift \
    Tests/DeviceRoundTwoChecks.swift -o "$BUKO_AUTOFILL_DIR/checks"
"$BUKO_AUTOFILL_DIR/checks" "$BUKO_AUTOFILL_DIR/library" "$@"
