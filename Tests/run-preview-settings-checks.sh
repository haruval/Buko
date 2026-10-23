#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
BUKO_PREVIEW_SIM="${1:?Pass an already booted simulator UUID}"
BUKO_PREVIEW_DIR="$(mktemp -d /private/tmp/BukoPreviewUI.XXXXXX)"
export BUKO_PREVIEW_DIR
python3 - <<'PY'
import os, pathlib, shutil
root = pathlib.Path(os.environ['BUKO_PREVIEW_DIR'])
for name in ['Buko', 'Buko.xcodeproj', 'Configuration']:
    shutil.copytree(name, root / name)
(root / 'Tests/UI').mkdir(parents=True)
for name in ['LectureSourceTests.swift', 'PreviewSettingsTests.swift']:
    shutil.copyfile('Tests/UI/' + name, root / 'Tests/UI' / name)
project = root / 'Buko.xcodeproj/project.pbxproj'
project.write_text(project.read_text().replace('"devplaceholder.$(PROJECT_UNIQUE_VALUE:identifier).$(PRODUCT_NAME:rfc1034identifier)"', 'dev.buko.PreviewValidation'))
PY
printf 'Source/settings UI harness: %s\n' "$BUKO_PREVIEW_DIR"
# This bundle belongs only to this disposable suite, never the user's Buko app.
xcrun simctl uninstall "$BUKO_PREVIEW_SIM" dev.buko.PreviewValidation >/dev/null 2>&1 || true
xcodebuild -project "$BUKO_PREVIEW_DIR/Buko.xcodeproj" -scheme BukoValidation -configuration Debug \
    -destination "id=$BUKO_PREVIEW_SIM" -derivedDataPath "$BUKO_PREVIEW_DIR/DerivedData" \
    -resultBundlePath "$BUKO_PREVIEW_DIR/Interactions.xcresult" CODE_SIGNING_ALLOWED=NO \
    test > "$BUKO_PREVIEW_DIR/ui-test.log" 2>&1
printf 'PASS: source grid, PDF presentation, deletion, isolation and detailed-preview settings\n'
