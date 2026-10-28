#!/usr/bin/env python3
"""Copy the integrated app and add synthetic UI fixtures only in the disposable copy."""
import argparse, hashlib, json, pathlib, shutil
p=argparse.ArgumentParser(); p.add_argument('destination',type=pathlib.Path); a=p.parse_args()
repo=pathlib.Path(__file__).resolve().parents[2]; experiment=pathlib.Path(__file__).resolve().parent
root=a.destination.resolve()
if root.is_relative_to(repo): raise ValueError('Choose a new directory outside the app repository')
root.mkdir(parents=True,exist_ok=False)
for name in ['Buko','Buko.xcodeproj','Configuration']: shutil.copytree(repo/name,root/name)
(root/'Tests/UI').mkdir(parents=True)
shutil.copyfile(experiment/'Integration/SpatialAppTests.swift',root/'Tests/UI/SpatialAppTests.swift')
p=root/'Buko.xcodeproj/project.pbxproj'
s=p.read_text().replace('dev.buko.LayoutExperiment.M4.UITests','dev.buko.SpatialIntegrationUITests').replace('dev.buko.LayoutExperiment.M4','dev.buko.SpatialIntegrationValidation')
p.write_text(s)
shutil.copyfile(experiment/'Integration/SpatialAppFixture.swift',root/'Buko/Development/SpatialAppFixture.swift')
# All live orchestration and spatial implementation come verbatim from the app.
# Raw capture persistence is a fixture-only observation hook.
p=root/'Buko/AI/SpatialCircleBridge.swift'; s=p.read_text()
needle='        return .init(original: .init(text: capture.text, context: capture.context,'
assert s.count(needle)==1
s=s.replace(needle,'''        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--spatial-fixture"), args.indices.contains(index + 1) {
            let root = URL.documentsDirectory.appendingPathComponent("SpatialEvidence", isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? JSONEncoder().encode(capture).write(to: root.appendingPathComponent("capture-\\(args[index + 1])-\\(UUID().uuidString).json"), options: .atomic)
        }
''' + needle)
p.write_text(s)
p=root/'Buko/ContentView.swift'; s=p.read_text()
s=s.replace('    @State private var saveTask:', '''    @State private var spatialOriginal: AutofillDocument?
    @State private var spatialReady = false
    @State private var spatialStatus = "idle"
    @State private var saveTask:''',1)
s=s.replace('        .ignoresSafeArea(.keyboard)', '''        .overlay(alignment: .bottomLeading) {
            VStack(alignment:.leading) {
                HStack {
                    Button("Load fixture") { setupSpatialFixture() }.accessibilityIdentifier("spatialSetup")
                    Button("Circle fixture") { captureSpatialFixture() }.disabled(!spatialReady).accessibilityIdentifier("spatialCapture")
                    Button("Checkpoint") { spatialCheckpoint("checkpoint") }.accessibilityIdentifier("spatialCheckpoint")
                }
                Text(spatialStatus).font(.system(size:9)).accessibilityIdentifier("spatialStatus")
                if spatialReady { Text("ready").font(.system(size:9)).accessibilityIdentifier("spatialReady") }
                if let intent = session.host?.circleIntent, intent.phase == .finished {
                    Text(intent.proposal == nil ? "no-proposal" : "proposal").font(.system(size:9)).accessibilityIdentifier("spatialResult")
                    Text(intent.missingInformation?.targets.map(\\.quote).joined(separator:",") ?? "none").font(.system(size:9)).accessibilityIdentifier("spatialTarget")
                        .accessibilityValue((intent.missingInformation?.informationNeeds.joined(separator:" ") ?? "") + " | " + (intent.proposal?.text ?? ""))
                }
            }.padding(10).background(.regularMaterial)
        }
        .onChange(of: session.host?.circleIntent.phase) { _, phase in
            if phase == .finished { spatialCheckpoint("finished") }
        }
        .ignoresSafeArea(.keyboard)''',1)
s=s.replace('    private func organize(', (experiment/'Integration/ContentViewHooks.swift.txt').read_text()+'\n    private func organize(',1)
p.write_text(s)
files=[]
for source in sorted((repo/'Buko').rglob('*')):
    if not source.is_file(): continue
    relative=source.relative_to(repo); copied=root/relative
    old=hashlib.sha256(source.read_bytes()).hexdigest(); new=hashlib.sha256(copied.read_bytes()).hexdigest()
    files.append({'path':str(relative),'original':old,'copy':new,'changed':old!=new})
assert {r['path'] for r in files if r['changed']}=={'Buko/ContentView.swift','Buko/AI/SpatialCircleBridge.swift'}
(root/'source-manifest.json').write_text(json.dumps({'files':files,'bundleID':'dev.buko.SpatialIntegrationValidation'},indent=2))
print(root)
