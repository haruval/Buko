#!/usr/bin/env python3
"""Assign and verify disposable simulator identities independently of production IDs."""
import argparse
import json
import pathlib
import plistlib
import re
import subprocess

IDENTITIES = {
    'dev.buko.PreviewValidation': 'dev.buko.PreviewValidation.UITests',
    'dev.buko.AutofillLibraryValidation': 'dev.buko.AutofillLibraryValidation.UITests',
    'dev.buko.InsertionValidation': 'dev.buko.InsertionValidation.UITests',
    'dev.buko.SpatialIntegrationValidation': 'dev.buko.SpatialIntegrationUITests',
}


def project_data(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))


def configure(project, app_id):
    test_id = IDENTITIES[app_id]
    project = pathlib.Path(project).resolve()
    repo = pathlib.Path(__file__).resolve().parents[1]
    if project.is_relative_to(repo):
        raise ValueError('Isolation changes belong only in a disposable project outside the repository')
    objects = project_data(project)['objects']
    text = project.read_text()
    targets = {obj['name']: obj for obj in objects.values() if obj.get('isa') == 'PBXNativeTarget'}
    if set(targets) != {'Buko', 'BukoUITests'}:
        raise ValueError('Unexpected targets; update isolation before running this project')
    for name, bundle_id in [('Buko', app_id), ('BukoUITests', test_id)]:
        configs = objects[targets[name]['buildConfigurationList']]['buildConfigurations']
        for identifier in configs:
            pattern = rf'(?ms)^\t\t{re.escape(identifier)} /\*[^\n]+\*/ = \{{.*?^\t\t\}};'
            matches = list(re.finditer(pattern, text))
            if len(matches) != 1:
                raise ValueError(f'Cannot locate configuration {identifier}')
            block = matches[0].group()
            replacement, count = re.subn(r'(?m)^(\s*PRODUCT_BUNDLE_IDENTIFIER = )[^;\n]+;',
                                         rf'\g<1>{bundle_id};', block)
            if count != 1:
                raise ValueError(f'Expected one explicit bundle ID in {identifier}')
            text = text[:matches[0].start()] + replacement + text[matches[0].end():]
    project.write_text(text)
    configured = project_data(project)['objects']
    for name, bundle_id in [('Buko', app_id), ('BukoUITests', test_id)]:
        for identifier in objects[targets[name]['buildConfigurationList']]['buildConfigurations']:
            if configured[identifier]['buildSettings']['PRODUCT_BUNDLE_IDENTIFIER'] != bundle_id:
                raise ValueError(f'Unisolated configuration: {identifier}')


def verify_products(derived_data, app_id, ui=True):
    test_id = IDENTITIES[app_id]
    products = pathlib.Path(derived_data).resolve() / 'Build/Products'
    bundles = {products / 'Debug-iphonesimulator/Buko.app': app_id}
    if ui:
        runner = products / 'Debug-iphonesimulator/BukoUITests-Runner.app'
        bundles[runner] = test_id + '.xctrunner'
        bundles[runner / 'PlugIns/BukoUITests.xctest'] = test_id
    verified = {}
    for bundle, expected in bundles.items():
        with (bundle / 'Info.plist').open('rb') as file:
            actual = plistlib.load(file).get('CFBundleIdentifier')
        if actual != expected:
            raise ValueError(f'Refusing installation: {bundle.name} has {actual!r}, expected {expected!r}')
        verified[str(bundle)] = actual
    run_files = list(products.glob('*.xctestrun')) if ui else []
    if ui and len(run_files) != 1:
        raise ValueError('Expected exactly one prepared xctestrun file')
    if ui:
        with run_files[0].open('rb') as file:
            run = plistlib.load(file)
        version = run.get('__xctestrun_metadata__', {}).get('FormatVersion')
        if version == 1:
            targets = [value for key, value in run.items() if key != '__xctestrun_metadata__']
        elif version == 2:
            targets = [target for config in run.get('TestConfigurations', [])
                       for target in config.get('TestTargets', [])]
        else:
            raise ValueError('Unknown xctestrun format; verify isolation before using it')
        expected = {
            'IsUITestBundle': True,
            'UITargetAppPath': '__TESTROOT__/Debug-iphonesimulator/Buko.app',
            'TestHostPath': '__TESTROOT__/Debug-iphonesimulator/BukoUITests-Runner.app',
            'TestHostBundleIdentifier': test_id + '.xctrunner',
            'TestBundlePath': '__TESTHOST__/PlugIns/BukoUITests.xctest',
        }
        if len(targets) != 1 or any(targets[0].get(key) != value for key, value in expected.items()):
            raise ValueError('Prepared UI tests do not target the isolated app')
    (products.parent.parent / 'verified-identities.json').write_text(json.dumps(verified, indent=2) + '\n')
    return run_files[0] if ui else next(iter(bundles))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['configure', 'verify'])
    parser.add_argument('path', type=pathlib.Path)
    parser.add_argument('app_id', choices=IDENTITIES)
    parser.add_argument('--app-only', action='store_true')
    args = parser.parse_args()
    if args.action == 'configure':
        configure(args.path, args.app_id)
    else:
        print(verify_products(args.path, args.app_id, ui=not args.app_only))
