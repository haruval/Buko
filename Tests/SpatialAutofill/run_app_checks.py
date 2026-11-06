#!/usr/bin/env python3
"""Run a disposable integration app; retain evidence even when a test fails."""
import argparse
import json
import os
import plistlib
from pathlib import Path
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('destination', type=Path)
parser.add_argument('simulator', help='An already booted simulator UUID')
parser.add_argument('--only', action='append', default=[])
args = parser.parse_args()
root = args.destination.resolve()
script = Path(__file__).resolve().parent
subprocess.run([sys.executable, str(script/'prepare_app.py'), str(root)], check=True)
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
env.pop('SDKROOT', None)
command = ['xcodebuild', '-project', str(root/'Buko.xcodeproj'), '-scheme', 'BukoValidation',
           '-configuration', 'Experiment Debug', '-destination', 'id='+args.simulator,
           '-derivedDataPath', str(root/'DerivedData'), 'CODE_SIGNING_ALLOWED=NO']
with (root/'build.log').open('w') as log:
    built = subprocess.run(command+['build-for-testing'], env=env, stdout=log, stderr=subprocess.STDOUT)
if built.returncode:
    sys.exit(built.returncode)
# Refuse installation if build/configuration changes escaped the fixture identity.
info=plistlib.loads((root/'DerivedData/Build/Products/Experiment Debug-iphonesimulator/Buko.app/Info.plist').read_bytes())
if (info.get('CFBundleIdentifier') != 'dev.buko.SpatialIntegrationValidation'
        or info.get('BukoIsolatedExperiment') is not True
        or info.get('BukoLayoutAutofillEnabled') is not True):
    raise RuntimeError('Refusing to test an app without the expected isolated spatial configuration')
tests = ['-only-testing:BukoUITests/SpatialAppTests/'+test for test in args.only] or ['-only-testing:BukoUITests/SpatialAppTests']
with (root/'test.log').open('w') as log:
    result = subprocess.run(command+['-resultBundlePath', str(root/'Tests.xcresult'), 'test-without-building']+tests,
                            env=env, stdout=log, stderr=subprocess.STDOUT)
container = subprocess.run(['xcrun','simctl','get_app_container',args.simulator,
                           'dev.buko.SpatialIntegrationValidation','data'],env=env,text=True,capture_output=True)
if container.returncode == 0:
    source = Path(container.stdout.strip())/'Documents/SpatialEvidence'
    if source.exists(): shutil.copytree(source,root/'evidence')
with (root/'export.log').open('w') as log:
    exported = subprocess.run(['xcrun','xcresulttool','export','attachments','--path',str(root/'Tests.xcresult'),
                              '--output-path',str(root/'attachments')],env=env,stdout=log,stderr=subprocess.STDOUT)
(root/'run-result.json').write_text(json.dumps({'testsExitCode':result.returncode,
    'evidenceCopied':(root/'evidence').exists(),'attachmentsExitCode':exported.returncode},indent=2))
print(root, flush=True)
sys.exit(result.returncode)
