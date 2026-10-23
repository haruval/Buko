#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUKO_GAP_RUN="$(mktemp -d /private/tmp/BukoGapBenchmark.XXXXXX)"
trap 'rm -rf "$BUKO_GAP_RUN"' EXIT
xcrun swiftc -module-cache-path "$BUKO_GAP_RUN/modules" \
    Buko/AI/PipelineDiagnostics.swift Buko/AI/IntentPrompts.swift Buko/AI/MissingInformationPlan.swift Buko/AI/CirclePlanner.swift \
    Buko/AI/MatrixProductCheck.swift Buko/AI/CircleCompletionRoute.swift \
    Buko/Retrieval/LectureRetrieval.swift Buko/Retrieval/GapRetrieval.swift \
    Buko/Retrieval/LectureLibrary.swift Buko/Retrieval/LecturePageExtractor.swift \
    Buko/Retrieval/LectureGroundingPolicy.swift Buko/Retrieval/LectureComposer.swift \
    Tests/GapBenchmarkSupport.swift Tests/GapRetrievalBenchmark.swift -o "$BUKO_GAP_RUN/benchmark"
"$BUKO_GAP_RUN/benchmark" --root "$BUKO_GAP_RUN/data" "$@"
