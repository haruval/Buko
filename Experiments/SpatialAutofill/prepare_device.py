#!/usr/bin/env python3
"""Optional capture-enabled copy. The branch root project builds directly."""
import argparse, hashlib, json, pathlib, shutil, subprocess
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('destination', type=pathlib.Path)
a = parser.parse_args()
experiment = pathlib.Path(__file__).resolve().parent
repo = experiment.parents[1]
root = a.destination.resolve()
if root.exists() or root.is_relative_to(repo):
    raise ValueError('Choose a new directory outside the app repository')
root.mkdir(parents=True)
for name in ['Buko', 'Buko.xcodeproj', 'Configuration']:
    shutil.copytree(repo/name, root/name, ignore=shutil.ignore_patterns('xcuserdata'))
# All configurations in a capture copy keep the experiment identity/store.
p=root/'Buko.xcodeproj/project.pbxproj'; s=p.read_text()
for original,replacement in [
    ('PRODUCT_BUNDLE_IDENTIFIER = "devplaceholder.$(PROJECT_UNIQUE_VALUE:identifier).$(PRODUCT_NAME:rfc1034identifier)";', 'PRODUCT_BUNDLE_IDENTIFIER = dev.buko.LayoutExperiment.M4;'),
    ('PRODUCT_BUNDLE_IDENTIFIER = dev.buko.UITests;', 'PRODUCT_BUNDLE_IDENTIFIER = dev.buko.LayoutExperiment.M4.UITests;'),
    ('REGISTER_APP_GROUPS = YES;', 'REGISTER_APP_GROUPS = NO;'),
    ('INFOPLIST_FILE = Configuration/Info.plist;', 'INFOPLIST_FILE = Configuration/ExperimentInfo.plist;')]:
    assert s.count(original)==2
    s=s.replace(original,replacement)
p.write_text(s)
(root/'Tests/UI').mkdir(parents=True)
shutil.copyfile(repo/'Tests/UI/SpatialDeviceSmokeTests.swift', root/'Tests/UI/SpatialDeviceSmokeTests.swift')
shutil.copyfile(experiment/'Integration/SpatialDeviceCapture.swift', root/'Buko/Development/SpatialDeviceCapture.swift')
p = root/'Buko/AI/SpatialCircleBridge.swift'
s = p.read_text()
needle = '        if mode == .standard {'
assert s.count(needle) == 1
s = s.replace(needle, "        await SpatialDeviceCapture.record(drawing: drawing, polygon: polygon)\n        try Task.checkCancellation()\n" + needle)
p.write_text(s)
schemes = root/'Buko.xcodeproj/xcshareddata/xcschemes'
for base in ['Buko Experiment', 'Buko Baseline']:
    tree = ET.parse(schemes/(base+'.xcscheme'))
    launch = tree.getroot().find('LaunchAction')
    arguments = launch.find('CommandLineArguments')
    if arguments is None: arguments = ET.SubElement(launch, 'CommandLineArguments')
    ET.SubElement(arguments, 'CommandLineArgument', argument='--spatial-record-capture', isEnabled='YES')
    ET.indent(tree)
    tree.write(schemes/(base+' Capture.xcscheme'), encoding='UTF-8', xml_declaration=True)
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
files = [dict(path=str(p.relative_to(repo)), original=digest(p), copy=digest(root/p.relative_to(repo)),
              changed=digest(p) != digest(root/p.relative_to(repo)))
         for p in sorted((repo/'Buko').rglob('*')) if p.is_file()]
assert {f['path'] for f in files if f['changed']} == {'Buko/AI/SpatialCircleBridge.swift'}
(root/'source-manifest.json').write_text(json.dumps(dict(files=files, bundleID='dev.buko.LayoutExperiment.M4',
    captureIsOptIn=True, gitHead=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'], text=True).strip()), indent=2))
print(root/'Buko.xcodeproj')
