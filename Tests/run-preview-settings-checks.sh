#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
BUKO_PREVIEW_SIM="${1:?Pass an already booted simulator UUID}"
BUKO_PREVIEW_DIR="$(mktemp -d /private/tmp/BukoPreviewUI.XXXXXX)"
BUKO_PREVIEW_MODE="${2:---all}"
export BUKO_PREVIEW_DIR BUKO_PREVIEW_MODE
python3 - <<'PY'
import os, pathlib, shutil
root = pathlib.Path(os.environ['BUKO_PREVIEW_DIR'])
for name in ['Buko', 'Buko.xcodeproj', 'Configuration']:
    shutil.copytree(name, root / name)
(root / 'Tests/UI').mkdir(parents=True)
if os.environ['BUKO_PREVIEW_MODE'] == '--zoom-only':
    shutil.copyfile('Tests/Fixtures/PDFZoomHarness.swift', root / 'Buko/MyApp.swift')
    shutil.copyfile('Tests/Fixtures/PDFZoomTests.swift', root / 'Tests/UI/PDFZoomTests.swift')
else:
    for name in ['LectureSourceTests.swift', 'PreviewSettingsTests.swift']:
        shutil.copyfile('Tests/UI/' + name, root / 'Tests/UI' / name)
# XCTest pinches begin at the target's corners. A central accessibility-only
# target keeps both real touches inside the PDF; no recognizer is replaced.
pdf = root / 'Buko/Views/LecturePDFView.swift'
pdf.write_text(pdf.read_text().replace('private final class SourcePDFView: PDFView {',
    'private final class SourcePDFView: PDFView {\n    private var zoomTestArea: PDFZoomTestArea?').replace(
    '        super.layoutSubviews()', '''        super.layoutSubviews()
        if zoomTestArea == nil {
            let area = PDFZoomTestArea(accessibilityContainer: self)
            area.pdf = self; area.accessibilityIdentifier = "pdfZoomTestArea"
            area.accessibilityLabel = "PDF zoom test area"
            zoomTestArea = area; accessibilityElements = [area]
        }
        zoomTestArea?.accessibilityFrameInContainerSpace = bounds.insetBy(dx: bounds.width * 0.25, dy: bounds.height * 0.25)
''') + '''
private final class PDFZoomTestArea: UIAccessibilityElement {
    weak var pdf: PDFView?
    override var accessibilityLabel: String? {
        get {
            guard let pdf, let document = pdf.document else { return nil }
            let center = CGPoint(x: pdf.bounds.midX, y: pdf.bounds.midY)
            guard let page = pdf.page(for: center, nearest: true) else { return nil }
            let point = pdf.convert(center, to: page)
            return String(format: "%d|%.3f|%.3f", document.index(for: page), point.x, point.y)
        }
        set { }
    }
    override var accessibilityValue: String? {
        get { guard let pdf else { return nil }; return String(format: "%.3f", pdf.scaleFactor / pdf.minScaleFactor) }
        set { }
    }
}
''')
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
printf 'PASS: preview UI checks (%s)\n' "$BUKO_PREVIEW_MODE"
