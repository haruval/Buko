"""Isolated app-only fixture and observations; model and production sources remain real."""
from pathlib import Path
import subprocess, sys, shutil, hashlib, json
repo = Path(__file__).resolve().parents[2]
root = Path(sys.argv[1]).resolve()
subprocess.run([sys.executable, str(repo/'Tests/DeviceRoundTwo/prepare_ui.py'), str(root)], check=True)
p = root/'Buko.xcodeproj/project.pbxproj'
p.write_text(p.read_text().replace('dev.buko.DeviceRoundTwoValidation', 'dev.buko.DuoUIValidation').replace('dev.buko.DeviceRoundTwoUITests', 'dev.buko.DuoUITests'))
for p in (root/'Tests/UI').glob('*.swift'): p.unlink()
shutil.copyfile(repo/'Tests/UI/DuoWorkspaceTests.swift', root/'Tests/UI/DuoWorkspaceTests.swift')
shutil.copyfile(repo/'Tests/UI/DuoChromeTests.swift', root/'Tests/UI/DuoChromeTests.swift')
shutil.copyfile(repo/'Tests/UI/DeviceRoundTwoTests.swift', root/'Tests/UI/DeviceRoundTwoTests.swift')
if '--production-ui' in sys.argv:
    # Actual-pose chrome checks attach to the running app after Device Hub changes
    # pose. Keep every app source exact, without a fixture strip taking bar space.
    shutil.rmtree(root/'Buko')
    shutil.copytree(repo/'Buko', root/'Buko')
    if '--finger-input' in sys.argv:
        p = root/'Buko/Canvas/CanvasSession.swift'
        p.write_text(p.read_text().replace('var allowsFingerDrawing = false', 'var allowsFingerDrawing = true'))
    files = []
    for p in sorted((repo/'Buko').rglob('*.swift')):
        relative = p.relative_to(repo)
        original = hashlib.sha256(p.read_bytes()).hexdigest()
        copied = hashlib.sha256((root/relative).read_bytes()).hexdigest()
        files.append({'path': str(relative), 'original': original, 'copy': copied, 'changed': original != copied})
    (root/'source-manifest.json').write_text(json.dumps({'files': files, 'bundleID': 'dev.buko.DuoUIValidation'}, indent=2))
    sys.exit(0)
p = root/'Buko/ContentView.swift'; s=p.read_text()
s=s.replace('    @State private var spatialOriginal:', '    @State private var duoFold = CommandLine.arguments.contains("--duo-fold-fixture") ? 1 : 0\n    @State private var duoCheck = "idle"\n    @State private var spatialOriginal:', 1)
s=s.replace('                    Button("Load fixture")', '''                    Button("Second note") {
                        createNote()
                        if let note = selectedNote { _ = renameNote(note, to: "Duo second note") }
                    }.accessibilityIdentifier("duoSecond")
                    Button("Append while running") { duoAppend() }.accessibilityIdentifier("duoAppend")
                    Text(duoCheck).font(.system(size: 8)).lineLimit(1).frame(width: 72, alignment: .leading).accessibilityIdentifier("duoCheck")
                    if CommandLine.arguments.contains("--duo-fold-fixture") { Button("Fold") { duoFold = (duoFold + 1) % 3 }.accessibilityIdentifier("duoFold") }
                    Button("Ink") { duoCheckpoint() }.accessibilityIdentifier("duoCheckpoint")
                    Button("Load fixture")''',1)
s=s.replace('    private func organize(', '''    private func duoCheckpoint() {
        _ = saveNow()
        let stored = (try? ModelContext(modelContext.container).fetch(FetchDescriptor<Note>())) ?? []
        func count(_ note: Note?) -> Int { note.flatMap { try? AutofillDocument.drawing($0.drawingData).strokes.count } ?? -1 }
        let canvas = session.canvas
        let width = Int((canvas?.bounds.width ?? 0).rounded())
        let paperWidth = Int((PageGeometry.pageWidth * (canvas?.zoomScale ?? 0)).rounded())
        let paperTop = Int((NotebookPaging.rect(for: selectedNote?.currentPageIndex ?? 0).minY * (canvas?.zoomScale ?? 0) - (canvas?.contentOffset.y ?? 0)).rounded())
        duoCheck = "viewportWidth=\(width);paperWidth=\(paperWidth);paperTop=\(paperTop);first=\(count(selectedNote));second=\(count(secondContent?.note));diskFirst=\(count(stored.first { $0.id == selectedNote?.id }));diskSecond=\(count(stored.first { $0.id == secondContent?.note?.id }));firstPolicy=\(session.canvas?.drawingPolicy.rawValue ?? 999);secondPolicy=\(secondSession.canvas?.drawingPolicy.rawValue ?? 999);firstEnabled=\(session.canvas?.drawingGestureRecognizer.isEnabled == true ? 1 : 0);secondEnabled=\(secondSession.canvas?.drawingGestureRecognizer.isEnabled == true ? 1 : 0);firstLive=\(session.canvas?.drawing.strokes.count ?? -1);secondLive=\(secondSession.canvas?.drawing.strokes.count ?? -1);sameManager=\(session.canvas?.undoManager === secondSession.canvas?.undoManager ? 1 : 0);firstOwner=\(session.host?.circleIntent.noteID == selectedNote?.id ? 1 : 0);secondOwner=\(secondSession.host?.circleIntent.noteID == secondContent?.note?.id ? 1 : 0)"
    }

    private func duoAppend() {
        captureSpatialFixture()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard let host = session.host, let note = selectedNote else { return }
            let running = host.circleIntent.processing
            host.canvas.delegate?.canvasViewDidBeginUsingTool?(host.canvas)
            let added = SpatialAppFixture.ink("New notes while autofill works", x: 60, y: 650, width: 700)
            host.canvas.drawing = PKDrawing(strokes: host.canvas.drawing.strokes + added.strokes)
            host.canvas.delegate?.canvasViewDrawingDidChange?(host.canvas)
            host.canvas.delegate?.canvasViewDidEndUsingTool?(host.canvas)
            duoCheck = "running=\\(running);preserved=\\(host.circleIntent.hasPreview);strokes=\\(host.canonicalDrawing.strokes.count)"
            // This becomes the exact pre-insertion Undo target, including new ink.
            spatialOriginal = AutofillDocument(note)
        }
    }

    private func organize(''',1)
# Synthetic reserved-region inputs exercise the view composition in both fold axes.
# The real Duo outer-display tests below do not pass this flag.
s=s.replace('!divisions.isEmpty', '(!divisions.isEmpty || duoFold > 0)')
s=s.replace('let fold = divisions.first(where: \\.isActive)?.frame', 'let fold = duoFold == 1 ? CGRect(x: outer.size.width / 2 - 20, y: 0, width: 40, height: outer.size.height) : duoFold == 2 ? CGRect(x: 0, y: outer.size.height / 2 - 20, width: outer.size.width, height: 40) : divisions.first(where: \\.isActive)?.frame')
s=s.replace('let activeFold = geometry.reservedRegions(kind: .division).first?.frame', 'let activeFold = duoFold == 1 ? CGRect(x: geometry.size.width / 2 - 20, y: 0, width: 40, height: geometry.size.height) : duoFold == 2 ? CGRect(x: 0, y: geometry.size.height / 2 - 20, width: geometry.size.width, height: 40) : geometry.reservedRegions(kind: .division).first?.frame')
# Finger input is enabled only in this isolated copy, so XCTest can deliver real canvas strokes.
s=s.replace('.id("\(note.id)-\(revision)")', '.id("\(note.id)-\(revision)").task(id: revision) { paneSession.allowsFingerDrawing = true }')
# Keep observations outside the navigation container. An outer safe-area inset
# can still overlap its native bottom toolbar on iPad after the sidebar changes.
s=s.replace('return workspace\n        .overlay(alignment: .bottomLeading) {',
            'return VStack(spacing: 0) {\n            workspace', 1)
# Keep the observation strip small enough for compact windows.
s=s.replace('Button("Check gesture")', 'Button("Gesture")').replace('Button("Check letters")', 'Button("Letters")')
s=s.replace('Button("Second note")','Button("Second")').replace('Button("Append while running")','Button("Append")')
s=s.replace('Button("Load fixture")','Button("Setup")').replace('Button("Circle fixture")','Button("Capture")')
s=s.replace('}.padding(10).background(.regularMaterial)', '}.font(.system(size: 9)).padding(6).background(.regularMaterial)')
p.write_text(s)
# Production now delegates editor/library displacement to the system overlay
# arrangement. Inject geometry only in the explicit iPad fold fixture; ordinary
# iPad and actual Duo runs still exercise Apple's native overlay implementation.
p = root/'Buko/ContentView.swift'; s = p.read_text()
s = s.replace('.arrangementViewStyle(.overlay.axes(secondContent == nil ? Axis.Set.horizontal.union(.vertical) : .horizontal))',
    '.arrangementViewStyle(DuoFixtureOverlayStyle(enabled: CommandLine.arguments.contains("--duo-fold-fixture"), fold: duoFold, hasSecond: secondContent != nil))')
s += '''
private struct DuoFixtureOverlayStyle: ArrangementViewStyle {
    let enabled: Bool
    let fold: Int
    let hasSecond: Bool
    func makeBody(configuration: Configuration) -> some View {
        if enabled {
            DuoFixtureOverlayLayout(fold: fold, hasSecond: hasSecond) {
                configuration.primary.zIndex(1)
                configuration.secondary.zIndex(0)
            }
        } else {
            ArrangementView(configuration)
                .arrangementViewStyle(.overlay.axes(hasSecond ? .horizontal : Axis.Set.horizontal.union(.vertical)))
        }
    }
}
private struct DuoFixtureOverlayLayout: Layout {
    let fold: Int
    let hasSecond: Bool
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let division: CGRect? = fold == 1 ? CGRect(x: bounds.width / 2 - 20, y: 0, width: 40, height: bounds.height)
            : fold == 2 && !hasSecond ? CGRect(x: 0, y: bounds.height / 2 - 20, width: bounds.width, height: 40) : nil
        let layout = WorkspaceGeometry(size: bounds.size, division: division, compact: false)
        for (index, view) in subviews.enumerated() {
            let rect = division == nil ? CGRect(origin: .zero, size: bounds.size) : (index == 0 ? layout.second : layout.first)
            view.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(rect.size))
        }
    }
}
'''
p.write_text(s)
