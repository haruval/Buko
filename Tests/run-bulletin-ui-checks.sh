#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
BUKO_BAND_SIM="${1:?Pass an already booted simulator UUID}"
shift
BUKO_BAND_DIR="$(mktemp -d /private/tmp/BukoBulletinUI.XXXXXX)"
export BUKO_BAND_DIR
python3 - <<'PY'
import os, pathlib, shutil
root = pathlib.Path(os.environ['BUKO_BAND_DIR'])
for name in ['Buko', 'Buko.xcodeproj', 'Configuration']:
    shutil.copytree(name, root / name)
(root / 'Tests/UI').mkdir(parents=True)
shutil.copyfile('Tests/UI/BulletinSidebarTests.swift', root / 'Tests/UI/BulletinSidebarTests.swift')
shutil.copyfile('Tests/UI/CircleIntentTests.swift', root / 'Tests/UI/CircleIntentTests.swift')
p = root / 'Buko.xcodeproj/project.pbxproj'
p.write_text(p.read_text().replace('"devplaceholder.$(PROJECT_UNIQUE_VALUE:identifier).$(PRODUCT_NAME:rfc1034identifier)"', 'dev.buko.BulletinValidation'))
# The copied app creates real authored ink for production recognition/review.
# Default fixtures invoke capture directly; --band-tool-fixture prepares ink only
# so the toolbar test must deliver actual one-pointer UIKit gestures.
p = root / 'Buko/ContentView.swift'; s = p.read_text()
s = s.replace('    @State private var showsBulletinBoard = false', '    @State private var bulletinTestOriginal: AutofillDocument?\n    @State private var showsBulletinBoard = false')
s = s.replace('        .ignoresSafeArea(.keyboard)', '''        .overlay(alignment: .bottomTrailing) {
            VStack {
                if let original = bulletinTestOriginal, let note = selectedNote, original.matches(AutofillDocument(note)) {
                    Text("Ink intact").accessibilityIdentifier("bulletinFixtureInkIntact")
                }
                Button("Capture fixture") { captureFixture() }.accessibilityIdentifier("captureBulletinFixture")
            }.padding(30)
        }
        .ignoresSafeArea(.keyboard)''', 1)
s = s.replace('    private func organize(', '''    private func captureFixture() {
        guard flushDrawing() else { return }
        let note = Note(title: availableTitle("Bulletin fixture"))
        note.pageLayoutVersion = 2
        note.drawingData = LectureHandwriting.drawing(pages: [["Exam in 12 days", "Review recursion later today"]]).dataRepresentation()
        guard performEdit({
            try note.setPages([NotebookPage()]); modelContext.insert(note)
        }) else { return }
        resetCanvas(); selection = note; sidebarVisible = false
        Task { @MainActor in
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(100))
                if let host = session.host, host.circleIntent.noteID == note.id, host.bounds.width > 0 {
                    _ = flushDrawing()
                    bulletinTestOriginal = AutofillDocument(note)
                    if ProcessInfo.processInfo.arguments.contains("--band-tool-fixture") { return }
                    host.onBandSelection?(host.canonicalDrawing, CGRect(x: PageGeometry.pageOriginX + 55, y: 125, width: 650, height: 105))
                    return
                }
            }
        }
    }

    private func organize(''', 1)
p.write_text(s)
PY
printf 'Isolated bulletin UI harness: %s\n' "$BUKO_BAND_DIR"
xcrun simctl uninstall "$BUKO_BAND_SIM" dev.buko.BulletinValidation >/dev/null 2>&1 || true
xcodebuild -project "$BUKO_BAND_DIR/Buko.xcodeproj" -scheme BukoValidation -configuration Debug \
    -destination "id=$BUKO_BAND_SIM" -derivedDataPath "$BUKO_BAND_DIR/DerivedData" \
    -resultBundlePath "$BUKO_BAND_DIR/Interactions.xcresult" CODE_SIGNING_ALLOWED=NO \
    test "$@" > "$BUKO_BAND_DIR/ui-test.log" 2>&1
printf 'PASS: bulletin sidebar UI checks\n'
