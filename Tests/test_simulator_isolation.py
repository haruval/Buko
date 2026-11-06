import pathlib
import plistlib
import tempfile
import unittest

from simulator_isolation import IDENTITIES, configure, project_data, verify_products

REPO = pathlib.Path(__file__).resolve().parents[1]


class SimulatorIsolationChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='BukoIsolationChecks-', dir='/private/tmp')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.app_id = 'dev.buko.PreviewValidation'
        self.test_id = IDENTITIES[self.app_id]

    def fixture(self, version=1):
        products = self.root / 'Build/Products'
        runner = products / 'Debug-iphonesimulator/BukoUITests-Runner.app'
        bundles = {
            products / 'Debug-iphonesimulator/Buko.app': self.app_id,
            runner: self.test_id + '.xctrunner',
            runner / 'PlugIns/BukoUITests.xctest': self.test_id,
        }
        for path, identifier in bundles.items():
            path.mkdir(parents=True, exist_ok=True)
            (path / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': identifier}))
        target = {
            'IsUITestBundle': True,
            'UITargetAppPath': '__TESTROOT__/Debug-iphonesimulator/Buko.app',
            'TestHostPath': '__TESTROOT__/Debug-iphonesimulator/BukoUITests-Runner.app',
            'TestHostBundleIdentifier': self.test_id + '.xctrunner',
            'TestBundlePath': '__TESTHOST__/PlugIns/BukoUITests.xctest',
        }
        run = {'BukoUITests': target} if version == 1 else {'TestConfigurations': [{'TestTargets': [target]}]}
        run['__xctestrun_metadata__'] = {'FormatVersion': version}
        manifest = products / 'Buko.xctestrun'
        manifest.write_bytes(plistlib.dumps(run))
        return bundles, manifest, run

    def test_all_configurations_survive_production_id_changes(self):
        for app_id in IDENTITIES:
            with self.subTest(app_id=app_id):
                project = self.root / 'project.pbxproj'
                text = (REPO / 'Buko.xcodeproj/project.pbxproj').read_text()
                project.write_text(text.replace('com.arigladstone.buko', 'org.future.renamed-app'))
                configure(project, app_id)
                ids = {obj['buildSettings']['PRODUCT_BUNDLE_IDENTIFIER']
                       for obj in project_data(project)['objects'].values()
                       if 'PRODUCT_BUNDLE_IDENTIFIER' in obj.get('buildSettings', {})}
                self.assertEqual(ids, {app_id, IDENTITIES[app_id]})

    def test_primary_checkout_cannot_be_rewritten(self):
        with self.assertRaises(ValueError):
            configure(REPO / 'Buko.xcodeproj/project.pbxproj', self.app_id)

    def test_both_xctestrun_formats(self):
        for version in [1, 2]:
            with self.subTest(version=version):
                _, manifest, _ = self.fixture(version)
                self.assertEqual(verify_products(self.root, self.app_id), manifest)

    def test_app_runner_and_test_bundle_must_each_be_isolated(self):
        bundles, _, _ = self.fixture()
        for bundle, expected in bundles.items():
            for incorrect in ['com.arigladstone.buko', 'com.arigladstone.buko.experiment', 'dev.buko.LayoutExperiment.M4']:
                with self.subTest(bundle=bundle.name, incorrect=incorrect):
                    (bundle / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': incorrect}))
                    with self.assertRaises(ValueError):
                        verify_products(self.root, self.app_id)
                    (bundle / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': expected}))

    def test_manifest_cannot_redirect_to_another_app_or_runner(self):
        for field in ['UITargetAppPath', 'TestHostPath', 'TestHostBundleIdentifier', 'TestBundlePath']:
            with self.subTest(field=field):
                _, manifest, run = self.fixture()
                run['BukoUITests'][field] = 'com.arigladstone.buko'
                manifest.write_bytes(plistlib.dumps(run))
                with self.assertRaises(ValueError):
                    verify_products(self.root, self.app_id)

    def test_extra_prepared_test_target_is_rejected(self):
        _, manifest, run = self.fixture()
        run['UnexpectedUITests'] = dict(run['BukoUITests'])
        manifest.write_bytes(plistlib.dumps(run))
        with self.assertRaises(ValueError):
            verify_products(self.root, self.app_id)

    def test_unregistered_identity_is_rejected(self):
        with self.assertRaises(KeyError):
            verify_products(self.root, 'com.arigladstone.buko')


if __name__ == '__main__':
    unittest.main()
