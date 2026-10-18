#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUKO_POLICY_DIR="$(mktemp -d /private/tmp/BukoGroundingPolicy.XXXXXX)"
trap 'rm -rf "$BUKO_POLICY_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUKO_POLICY_DIR/modules" \
    Buko/Retrieval/LectureRetrieval.swift Buko/Retrieval/LectureGroundingPolicy.swift \
    Buko/AI/MatrixProductCheck.swift Buko/AI/CircleCompletionRoute.swift \
    Tests/LectureGroundingPolicyChecks.swift -o "$BUKO_POLICY_DIR/checks"
"$BUKO_POLICY_DIR/checks"
