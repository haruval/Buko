"""Disposable app with authored ink and source PDFs; production model flow is unchanged."""
from pathlib import Path
import subprocess, sys, shutil
repo = Path(__file__).resolve().parents[2]
root = Path(sys.argv[1]).resolve()
subprocess.run([sys.executable, str(repo/'Tests/SpatialAutofill/prepare_app.py'), str(root)], check=True)
project = root/'Buko.xcodeproj/project.pbxproj'
project.write_text(project.read_text().replace('dev.buko.SpatialIntegrationValidation', 'dev.buko.DeviceRoundTwoValidation').replace('dev.buko.SpatialIntegrationUITests', 'dev.buko.DeviceRoundTwoUITests'))
for p in (root/'Tests/UI').glob('*.swift'): p.unlink()
for name in ['PhysicalFeedbackTests.swift', 'DeviceRoundTwoTests.swift']:
    shutil.copyfile(repo/'Tests/UI'/name, root/'Tests/UI'/name)
shutil.copyfile(repo/'Tests/Fixtures/RoundTwoGestureChecks.swift', root/'Buko/Development/RoundTwoGestureChecks.swift')
shutil.copyfile(repo/'Tests/Fixtures/RoundTwoHandwritingChecks.swift', root/'Buko/Development/RoundTwoHandwritingChecks.swift')
p = root/'Buko/Development/SpatialAppFixture.swift'
s = p.read_text().replace('static var pdfName: String {', 'static var pdfName: String { if name == "auth" { return "roundTwoSecurity" }; return')
s = s.replace('        switch name {', '''        switch name {
        case "auth":
            rows = [("authentication vs authorization:",60,220,800)]''', 1)
p.write_text(s)
p = root/'Buko/ContentView.swift'
s = p.read_text().replace('    @State private var spatialOriginal:', '    @State private var roundTwoLetterStatus = "not checked"\n    @State private var roundTwoGestureStatus = "not checked"\n    @State private var spatialOriginal:', 1)
s = s.replace('                    Button("Load fixture")', '''                    Button("Check gesture") { roundTwoGestureStatus = RoundTwoGestureChecks.run() }.accessibilityIdentifier("checkGestureLogic")
                    Text(roundTwoGestureStatus).font(.system(size:8)).accessibilityIdentifier("gestureLogicStatus")
                    Button("Check letters") { Task { roundTwoLetterStatus = await RoundTwoHandwritingChecks.run() } }.accessibilityIdentifier("checkLetters")
                    Text(roundTwoLetterStatus).font(.system(size:8)).accessibilityIdentifier("letterLogicStatus")
                    Button("Load fixture")''', 1)
s = s.replace('if phase == .finished { spatialCheckpoint("finished") }', 'if phase == .finished { spatialCheckpoint("finished"); roundTwoSaveTrace() }')
s = s.replace('    private func organize(', '''    private func roundTwoSaveTrace() {
        guard let state = session.host?.circleIntent else { return }
        let trace = state.pipeline.steps.map { [$0.id, $0.instructions ?? "", $0.input, $0.summary].joined(separator: "\\n") }.joined(separator: "\\n\\n")
        let url = URL.documentsDirectory.appendingPathComponent("SpatialEvidence/trace-\\(SpatialAppFixture.name)-\\(UUID()).txt")
        try? trace.write(to: url, atomically: true, encoding: .utf8)
    }

    private func organize(''', 1)
p.write_text(s)
# Create a real, native-text PDF without requiring an extra Python dependency.
# PDF object IDs, offsets and stream lengths are derived from the fixture text.
pages = ["Authentication: establish the account.", "Authorization: decide the allowed action."]
objects = [b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [4 0 R 6 0 R] /Count 2 >>', b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
for i, text in enumerate(pages):
    stream = f'BT /F1 16 Tf 40 690 Td ({text}) Tj ET'.encode()
    objects += [f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents {5+i*2} 0 R >>'.encode(), b'<< /Length '+str(len(stream)).encode()+b' >>\nstream\n'+stream+b'\nendstream']
pdf = bytearray(b'%PDF-1.4\n'); offsets = [0]
for i, obj in enumerate(objects,1):
    offsets.append(len(pdf)); pdf += f'{i} 0 obj\n'.encode()+obj+b'\nendobj\n'
xref = len(pdf); pdf += f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode()
for offset in offsets[1:]: pdf += f'{offset:010d} 00000 n \n'.encode()
pdf += f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
(root/'Buko/Resources/Lectures/roundTwoSecurity.pdf').write_bytes(pdf)
print(root)
