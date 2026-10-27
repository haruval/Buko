#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
BUKO_AUTOFILL_LIBRARY_SIM="${1:?Pass an already booted simulator UUID}"
shift
BUKO_AUTOFILL_LIBRARY_DIR="$(mktemp -d /private/tmp/BukoAutofillLibraryUI.XXXXXX)"
export BUKO_AUTOFILL_LIBRARY_DIR
python3 - <<'PY'
import os, pathlib, shutil
root = pathlib.Path(os.environ['BUKO_AUTOFILL_LIBRARY_DIR'])
for name in ['Buko', 'Buko.xcodeproj', 'Configuration']:
    shutil.copytree(name, root / name)
(root / 'Tests/UI').mkdir(parents=True)
shutil.copyfile('Tests/UI/AutofillLibraryTests.swift', root / 'Tests/UI/AutofillLibraryTests.swift')
shutil.copyfile('Tests/UI/CircleIntentTests.swift', root / 'Tests/UI/CircleIntentTests.swift')
p = root / 'Buko.xcodeproj/project.pbxproj'
p.write_text(p.read_text().replace('"devplaceholder.$(PROJECT_UNIQUE_VALUE:identifier).$(PRODUCT_NAME:rfc1034identifier)"', 'dev.buko.AutofillLibraryValidation'))
# The copied app circles authored ink through production recognition/planning.
# Only selection delivery and read-only diagnostics are test-only.
p = root / 'Buko/ContentView.swift'; s = p.read_text()
s = s.replace('    @State private var saveTask:', '    @State private var circleTestOriginal: AutofillDocument?\n    @State private var saveTask:', 1)
s = s.replace('        .ignoresSafeArea(.keyboard)', '''        .overlay(alignment: .bottomTrailing) {
            VStack {
                if let original = circleTestOriginal, let note = selectedNote, original.matches(AutofillDocument(note)) {
                    Text("Ink intact").accessibilityIdentifier("circleFixtureInkIntact")
                }
                if let intent = session.host?.circleIntent, intent.phase == .finished {
                    Text(intent.clarification.isEmpty ? "finished" : "clarify").accessibilityIdentifier("circleFixtureResult")
                    Text(intent.pipeline.steps.map(\.id).joined(separator: ",")).accessibilityIdentifier("circleFixtureStages")
                    Text(intent.recognizedText).accessibilityIdentifier("circleFixtureRecognition")
                }
                Button("Capture fixture") { captureFixture() }.accessibilityIdentifier("captureCircleFixture")
            }.padding(30)
        }
        .ignoresSafeArea(.keyboard)''', 1)
s = s.replace('    private func organize(', '''    private func captureFixture() {
        guard flushDrawing() else { return }
        let note = Note(title: availableTitle("PPL"))
        note.pageLayoutVersion = 2
        let arguments = ProcessInfo.processInfo.arguments
        let lines: [String]
        if arguments.contains("--circle-heading") { lines = ["Closure:", "Exam in 12 days"] }
        else if arguments.contains("--circle-parallel") { lines = ["Lexical analysis produces tokens.", "Parsing:"] }
        else { lines = ["What should I review before the exam?"] }
        note.drawingData = LectureHandwriting.drawing(pages: [lines]).dataRepresentation()
        guard performEdit({
            try note.setPages([NotebookPage()]); modelContext.insert(note)
        }) else { return }
        resetCanvas(); selection = note; sidebarVisible = false
        Task { @MainActor in
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                if let host = session.host, host.circleIntent.noteID == note.id, host.bounds.width > 0 {
                    _ = flushDrawing()
                    circleTestOriginal = AutofillDocument(note)
                    let multiline = arguments.contains("--circle-parallel")
                    let rect = CGRect(x: PageGeometry.pageOriginX + 45, y: multiline ? 55 : 110, width: 710, height: multiline ? 260 : 80)
                    let polygon = (0..<80).map { i in
                        let angle = CGFloat(i) * 2 * .pi / 79
                        return CGPoint(x: rect.midX + rect.width / 2 * cos(angle), y: rect.midY + rect.height / 2 * sin(angle))
                    }
                    let screen = polygon.map { CGPoint(x: $0.x * host.canvas.zoomScale - host.canvas.contentOffset.x,
                                                       y: $0.y * host.canvas.zoomScale - host.canvas.contentOffset.y) }
                    host.circleIntent.analyze(drawing: host.canonicalDrawing, polygon: polygon, screenPolygon: screen,
                                              scale: host.canvas.zoomScale, offset: host.canvas.contentOffset)
                    return
                }
            }
        }
    }

    private func organize(''', 1)
assert 'private var circleTestOriginal: AutofillDocument?' in s
assert 'captureCircleFixture' in s
p.write_text(s)
PY
printf 'Isolated autofill/library UI harness: %s\n' "$BUKO_AUTOFILL_LIBRARY_DIR"
xcrun simctl uninstall "$BUKO_AUTOFILL_LIBRARY_SIM" dev.buko.AutofillLibraryValidation >/dev/null 2>&1 || true
xcodebuild -project "$BUKO_AUTOFILL_LIBRARY_DIR/Buko.xcodeproj" -scheme BukoValidation -configuration Debug \
    -destination "id=$BUKO_AUTOFILL_LIBRARY_SIM" -derivedDataPath "$BUKO_AUTOFILL_LIBRARY_DIR/DerivedData" \
    -resultBundlePath "$BUKO_AUTOFILL_LIBRARY_DIR/Interactions.xcresult" CODE_SIGNING_ALLOWED=NO \
    test "$@" > "$BUKO_AUTOFILL_LIBRARY_DIR/ui-test.log" 2>&1
printf 'PASS: autofill/library UI checks\n'
