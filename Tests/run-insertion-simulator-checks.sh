#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
BUKO_INSERTION_SIM="${1:?Pass an already booted simulator UUID}"
BUKO_INSERTION_MODE="${2:---run-checks}"
BUKO_INSERTION_HARNESS="$(mktemp -d /private/tmp/BukoInsertionSimulator.XXXXXX)"
export BUKO_INSERTION_HARNESS
python3 - <<'PY'
import os, pathlib, shutil
root = pathlib.Path(os.environ['BUKO_INSERTION_HARNESS'])
for name in ['Buko', 'Buko.xcodeproj', 'Configuration']:
    shutil.copytree(name, root / name)
shutil.copyfile('Tests/Fixtures/AutofillRuntimeHarness.swift', root / 'Buko/MyApp.swift')
(root / 'Tests/UI').mkdir(parents=True)
shutil.copyfile('Tests/Fixtures/AutofillInteractionTests.swift', root / 'Tests/UI/AutofillInteractionTests.swift')
project = root / 'Buko.xcodeproj/project.pbxproj'
project.write_text(project.read_text().replace('"devplaceholder.$(PROJECT_UNIQUE_VALUE:identifier).$(PRODUCT_NAME:rfc1034identifier)"', 'dev.buko.InsertionValidation'))
# A same-file test accessor keeps fixture injection out of production code.
with (root / 'Buko/AI/CircleIntentState.swift').open('a') as f:
    f.write('''
extension CircleIntentState {
    func validationBegin(_ value: AutofillProposal, scale: CGFloat, offset: CGPoint) {
        captureScale = scale; captureOffset = offset; projection = .identity
        selectionBounds = CircleGeometry.path(value.selectionPolygon).boundingBoxOfPath
            .applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: -offset.x, ty: -offset.y))
        closedAt = Date.timeIntervalSinceReferenceDate
        closedBoundary = CircleJellyGeometry.roundedRectangle(selectionBounds)
        phase = .inferring
    }
    func validationPreview(_ value: AutofillProposal, scale: CGFloat, offset: CGPoint) {
        validationBegin(value, scale: scale, offset: offset)
        phase = .finished; intent = "Complete Parsing"; action = "Insert a short definition after the heading’s colon."
        recognizedText = value.selectedText; nearbyContext = "Lexical analysis groups characters into tokens."
        evidence = value.selectedText; citations = value.citations
        pipeline.receive(.began(id: "intent", title: "Infer intent", instructions: IntentPrompts.instructions,
            input: IntentPrompts.request(selected: value.selectedText, context: nearbyContext)))
        pipeline.receive(.completed(id: "intent", summary: intent))
        pipeline.receive(.began(id: "retrieval", title: "Search lecture PDFs", instructions: nil, input: value.selectedText))
        pipeline.receive(.completed(id: "retrieval", summary: "Fixture passages retrieved"))
        proposal = value
    }
}
''')
with (root / 'Buko/AI/AutofillCanvasPreview.swift').open('a') as f:
    f.write('''
extension AutofillCanvasPreview {
    var validationMotion: (visible: Bool, positions: [CGFloat], velocities: [CGFloat], targets: [CGFloat], alpha: CGFloat) {
        let now = CACurrentMediaTime()
        return (!isHidden, bands.map { $0.spring.sample(at: now).position },
                bands.map { $0.spring.sample(at: now).velocity }, bands.map { $0.spring.target }, insertedCanvas.alpha)
    }
}
''')
with (root / 'Buko/Canvas/CanvasHostView.swift').open('a') as f:
    f.write('''
extension CanvasHostView {
    var validationMotion: (visible: Bool, positions: [CGFloat], velocities: [CGFloat], targets: [CGFloat], alpha: CGFloat) {
        autofillPreview.validationMotion
    }
    var validationDisplayedPages: Int { displayedPageCount }
    func validationShow(_ value: AutofillLayout.Result) { showAutofillPreview(value) }
}
''')
PY
if [[ "$BUKO_INSERTION_MODE" == "--ui-checks" ]]; then
    xcodebuild -project "$BUKO_INSERTION_HARNESS/Buko.xcodeproj" -scheme BukoValidation -configuration Debug \
        -destination "id=$BUKO_INSERTION_SIM" -derivedDataPath "$BUKO_INSERTION_HARNESS/DerivedData" \
        -resultBundlePath "$BUKO_INSERTION_HARNESS/Interactions.xcresult" CODE_SIGNING_ALLOWED=NO \
        test > "$BUKO_INSERTION_HARNESS/ui-test.log" 2>&1
    printf 'UI validation: %s\n' "$BUKO_INSERTION_HARNESS"
    exit 0
fi
xcodebuild -project "$BUKO_INSERTION_HARNESS/Buko.xcodeproj" -scheme Buko -configuration Debug \
    -sdk iphonesimulator -destination "id=$BUKO_INSERTION_SIM" \
    -derivedDataPath "$BUKO_INSERTION_HARNESS/DerivedData" CODE_SIGNING_ALLOWED=NO \
    PRODUCT_BUNDLE_IDENTIFIER=dev.buko.InsertionValidation build > "$BUKO_INSERTION_HARNESS/build.log" 2>&1
xcrun simctl install "$BUKO_INSERTION_SIM" "$BUKO_INSERTION_HARNESS/DerivedData/Build/Products/Debug-iphonesimulator/Buko.app"
BUKO_INSERTION_DATA="$(xcrun simctl get_app_container "$BUKO_INSERTION_SIM" dev.buko.InsertionValidation data)"
rm -f "$BUKO_INSERTION_DATA/Documents/result.txt"
xcrun simctl launch --terminate-running-process "$BUKO_INSERTION_SIM" dev.buko.InsertionValidation "$BUKO_INSERTION_MODE"
printf 'Harness: %s\nData: %s\n' "$BUKO_INSERTION_HARNESS" "$BUKO_INSERTION_DATA"
if [[ "$BUKO_INSERTION_MODE" == "--run-checks" || "$BUKO_INSERTION_MODE" == "--motion-checks" ]]; then
    for attempt in {1..120}; do
        if [[ -f "$BUKO_INSERTION_DATA/Documents/result.txt" ]]; then
            cat "$BUKO_INSERTION_DATA/Documents/result.txt"
            if [[ "$BUKO_INSERTION_MODE" == "--motion-checks" ]]; then
                mkdir -p "$BUKO_INSERTION_HARNESS/frames"
                cp "$BUKO_INSERTION_DATA"/Documents/reflow-*.png "$BUKO_INSERTION_HARNESS/frames/"
            fi
            if [[ "$(head -c 4 "$BUKO_INSERTION_DATA/Documents/result.txt")" == "PASS" ]]; then exit 0; else exit 1; fi
        fi
        sleep 1
    done
    echo 'No result written; inspect the isolated app crash log.' >&2
    exit 1
fi
