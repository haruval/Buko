#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUKO_RAG_CHECK_DIR="$(mktemp -d /private/tmp/BukoRAGChecks.XXXXXX)"
trap 'rm -rf "$BUKO_RAG_CHECK_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUKO_RAG_CHECK_DIR/modules" \
    Buko/Retrieval/LectureRetrieval.swift Buko/Retrieval/LectureLibrary.swift \
    Tests/LectureRetrievalChecks.swift -o "$BUKO_RAG_CHECK_DIR/checks"
"$BUKO_RAG_CHECK_DIR/checks" "$BUKO_RAG_CHECK_DIR" "$PWD/Buko/Resources/Lectures" "${1:-/private/tmp/buko-rag-evaluation.json}"
