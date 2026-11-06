"""Build spatial regression checks from hash-recorded app sources."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
FILES = [
    'Buko/AppBuildConfiguration.swift', 'Buko/AI/SpatialPlanner.swift', 'Buko/AI/SpatialScopeCue.swift', 'Buko/AI/SpatialInkReader.swift', 'Buko/AI/SpatialCircleBridge.swift',
    'Buko/AI/PipelineDiagnostics.swift', 'Buko/AI/IntentPrompts.swift',
    'Buko/AI/MissingInformationPlan.swift', 'Buko/AI/CirclePlanner.swift',
    'Buko/AI/AutofillProposal.swift', 'Buko/AI/AutofillWriter.swift',
    'Buko/Retrieval/GapRetrieval.swift', 'Buko/Retrieval/LectureRetrieval.swift',
    'Buko/Retrieval/LectureGroundingPolicy.swift', 'Buko/Retrieval/LectureComposer.swift',
    'Buko/Retrieval/LectureLibrary.swift', 'Buko/Retrieval/LecturePageExtractor.swift',
    'Buko/AI/CircleInkReader.swift', 'Buko/AI/CircleGeometry.swift',
    'Buko/Canvas/PageGeometry.swift', 'Buko/Canvas/NotebookPaging.swift',
    'Buko/Canvas/MonochromeInk.swift', 'Buko/AI/HandwritingSamples.swift',
    'Buko/AI/HandwrittenFont.swift', 'Buko/Development/LectureHandwriting.swift',
    'Tests/ContextualIntentChecks.swift']

def prepare(destination, instrument_reader=False):
    dest = Path(destination).resolve()
    if dest.exists() or dest.is_relative_to(ROOT):
        raise ValueError('Choose a new directory outside the app repository')
    (dest / 'Sources').mkdir(parents=True)
    manifest = {'formatVersion': 1, 'sources': {}}
    for name in FILES:
        original = (ROOT / name).read_text()
        copied = original
        if instrument_reader and name.endswith('CircleInkReader.swift'):
            boundary = 'func read(drawing: PKDrawing, polygon: [CGPoint]) async throws -> Result {'
            assert copied.count(boundary) == 1
            copied = copied.replace(boundary, boundary + '\n        if await CaptureAuditCounter.shared.begin(strokes:drawing.strokes.count) { throw ReadError.unreadable }')
        if name.endswith('ContextualIntentChecks.swift'):
            boundary = '        if args.contains("--cancel-repair") {'
            assert copied.count(boundary) == 1
            copied = copied.replace(boundary, '''        if args.contains("--binding-ink") || args.contains("--capture-checks") || args.contains("--ink-guards") || args.contains("--cancel-spatial") || args.contains("--ink") || args.contains("--spatial") || args.contains("--self-check") {
            try await SpatialAudit.run(args: args, output: output)
            return
        }
''' + boundary)
            invocation = 'let result = try await CirclePlanner.infer(selected: item.selected, context: item.context, observer: observer)'
            assert copied.count(invocation) == 1
            copied = copied.replace(invocation, """let transcript = GapTranscript(selected:item.selected,context:item.context)
                let continuousRows = transcript.blocks.filter(\\.selected).enumerated().map { index,block in
                    SpatialLine(blockID:block.id,text:block.text,page:"p1",rect:[60,100+Double(index)*35,700,20])
                }
                let result = try await (args.contains("--layout-fallback")
                    ? SpatialPlanner.infer(selected:item.selected,context:item.context,lines:continuousRows,observer:observer)
                    : CirclePlanner.infer(selected:item.selected,context:item.context,observer:observer))""")
        (dest / 'Sources' / Path(name).name).write_text(copied)
        manifest['sources'][name] = {'originalSHA256': hashlib.sha256(original.encode()).hexdigest(),
                                    'generatedSHA256': hashlib.sha256(copied.encode()).hexdigest()}
    for source in (ROOT / 'Tests/SpatialAutofill/Sources').glob('*.swift'):
        shutil.copy2(source, dest / 'Sources' / source.name)
        manifest['sources'][str(source.relative_to(ROOT))] = {'originalSHA256': hashlib.sha256(source.read_bytes()).hexdigest()}
    (dest / 'source-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (dest / 'Package.swift').write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "BukoSpatialChecks", platforms: [.macOS("27.0")],
    targets: [.executableTarget(name: "buko-spatial", path: "Sources")], swiftLanguageModes: [.v5])
''')
    print(dest)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', required=True)
    parser.add_argument('--instrument-reader', action='store_true', help='Add reader-call accounting/fault injection to the disposable host copy only')
    args = parser.parse_args()
    prepare(args.destination, args.instrument_reader)
