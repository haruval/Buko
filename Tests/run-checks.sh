#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUKO_CHECK_DIR="$(mktemp -d /private/tmp/BukoChecks.XXXXXX)"
trap 'rm -rf "$BUKO_CHECK_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUKO_CHECK_DIR/modules" \
    Buko/Canvas/PageGeometry.swift Tests/PageGeometryChecks.swift \
    -o "$BUKO_CHECK_DIR/geometry"
"$BUKO_CHECK_DIR/geometry"
xcrun swiftc -module-cache-path "$BUKO_CHECK_DIR/modules" \
    Buko/Models/Note.swift Tests/NoteStorageChecks.swift \
    -o "$BUKO_CHECK_DIR/storage"
"$BUKO_CHECK_DIR/storage"
