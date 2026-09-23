"""Synthetic orchestration tests; these do not compile a Flutter engine."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_engine', ROOT / 'scripts/build_engine.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class EngineBuildTest(unittest.TestCase):
    def setUp(self):
        self.lock = json.loads((ROOT / 'toolchain.lock.json').read_text())

    def test_preflight_does_not_create_missing_workspace(self):
        with tempfile.TemporaryDirectory() as parent:
            workspace = Path(parent) / 'absent'
            report = module.preflight(workspace, self.lock, dict(os.environ), available=30 * 1024**3)
            self.assertTrue(report['errors'])
            self.assertFalse(workspace.exists())

    def test_no_execute_even_when_explicit_with_failed_gate(self):
        with tempfile.TemporaryDirectory() as parent:
            with patch('sys.argv', ['build_engine', '--build-root', parent, '--execute']), \
                 patch.object(module, 'preflight', return_value={'errors': ['space']}), \
                 patch.object(module, 'execute') as execute, patch('builtins.print'):
                self.assertEqual(module.main(), 2)
                execute.assert_not_called()

    def test_preserves_existing_output(self):
        with tempfile.TemporaryDirectory() as parent:
            workspace = Path(parent)
            existing = workspace / 'engine/engine/src/out/host_release_arm64'
            existing.mkdir(parents=True)
            (existing / 'keep').write_text('keep')
            report = module.preflight(workspace, self.lock, dict(os.environ), available=250 * 1024**3)
            self.assertTrue(any('Output already exists' in e for e in report['errors']))
            self.assertEqual((existing / 'keep').read_text(), 'keep')

    def test_recipes_keep_release_optimization_and_source_host_sdk(self):
        recipes = module.recipes()
        self.assertEqual([r[0] for r in recipes], ['host_release_arm64', 'android_release_arm64', 'ios_release'])
        self.assertIn('--no-prebuilt-dart-sdk', recipes[0][1])
        for _, flags, _ in recipes:
            self.assertIn('release', flags)
            self.assertNotIn('--unoptimized', flags)
            self.assertNotIn('--no-lto', flags)

    def test_mixed_mobile_recipes_are_isolated_and_keep_aot(self):
        recipes = module.recipes('mixed', ['android', 'ios'])
        self.assertEqual([r[0] for r in recipes], ['android_release_arm64_mixed', 'ios_release_mixed'])
        for name, flags, _ in recipes:
            self.assertEqual(flags[flags.index('--target-dir') + 1], name)
            self.assertIn('--dart-dynamic-modules', flags)
            self.assertIn('--no-prebuilt-dart-sdk', flags)
            self.assertEqual(flags[flags.index('--runtime-mode') + 1], 'release')
            self.assertNotIn('--unoptimized', flags)

    def test_resume_rejects_runtime_patch_drift(self):
        with self.assertRaisesRegex(ValueError, 'patch identity differs'):
            self.resume_fixture(profile='mixed', patch_drift=True)
        self.assertEqual(self.resume_fixture(profile='mixed'), ['host_release_arm64_mixed'])

    def test_mixed_source_change_during_build_fails(self):
        code, manifest, _ = self.run_fixture(profile='mixed', patch_drift=True)
        self.assertEqual(code, 2)
        self.assertIn('patch set changed', manifest['error'])

    def test_mixed_compile_still_not_runtime_acceptance(self):
        code, manifest, _ = self.run_fixture(profile='mixed')
        self.assertEqual(code, 0)
        self.assertFalse(manifest['runtime_implemented'])
        self.assertEqual(manifest['runtime_sources'], {'runtime_patchset_sha256': 'old'})

    def resume_fixture(self, state='failed', drift=False, profile='reference', patch_drift=False):
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent)
            workspace = root / 'workspace'
            path = root / 'output/engine-builds/fixture/build.json'
            path.parent.mkdir(parents=True)
            recipes = module.recipes(profile)
            previous = {'profile': profile, 'runtime_sources': {'runtime_patchset_sha256': 'old'}, 'state': state, 'workspace': str(workspace), 'lock': self.lock,
                        'recipes': [{'output': n, 'gn_flags': f, 'required_artifacts': a}
                                    for n, f, a in recipes],
                        'steps': [{'cwd': str(workspace / 'engine/engine/src'),
                                   'command': ['python3', 'flutter/tools/gn', *recipes[0][1]]}]}
            if drift:
                previous['recipes'][0]['gn_flags'] = ['--unoptimized']
            path.write_text(json.dumps(previous))
            with patch.object(module, 'ROOT', root), patch.object(module, 'verify_runtime_sources', return_value={'runtime_patchset_sha256': 'changed' if patch_drift else 'old'}):
                return module.validate_resume(path, workspace, self.lock, profile)

    def test_resume_only_authorizes_started_output(self):
        self.assertEqual(self.resume_fixture(), ['host_release_arm64'])

    def test_resume_rejects_successful_run(self):
        with self.assertRaises(ValueError):
            self.resume_fixture(state='compiled-not-device-validated')

    def test_resume_rejects_recipe_drift(self):
        with self.assertRaises(ValueError):
            self.resume_fixture(drift=True)

    def run_fixture(self, returncode=0, create_outputs=True, escaping=False, profile='reference', patch_drift=False):
        with tempfile.TemporaryDirectory() as parent:
            workspace = Path(parent)
            destination = workspace / 'logs'
            destination.mkdir()
            if create_outputs:
                for name, _, required in module.recipes(profile):
                    for relative in ['args.gn', *required]:
                        artifact = workspace / 'engine/engine/src/out' / name / relative
                        artifact.parent.mkdir(parents=True, exist_ok=True)
                        artifact.write_bytes(b'synthetic fixture, not engine evidence')
                if escaping:
                    artifact = workspace / 'engine/engine/src/out/host_release_arm64/dart-sdk/bin/dart'
                    artifact.unlink()
                    (workspace / 'outside').write_bytes(b'outside')
                    artifact.symlink_to(workspace / 'outside')

            def capture(command, cwd, env):
                if command[:3] == ['git', 'rev-parse', 'HEAD']:
                    key = 'dart_revision' if cwd.name == 'dart' else cwd.name + '_revision'
                    return self.lock[key]
                return ''

            with patch.object(module, 'capture', side_effect=capture), \
                 patch.object(module.subprocess, 'run', return_value=subprocess.CompletedProcess([], returncode)) as run, \
                 patch.object(module, 'verify_runtime_sources', return_value={'runtime_patchset_sha256': 'changed' if patch_drift else 'old'}):
                code = module.execute(workspace, {'lock': self.lock, 'profile': profile, 'runtime_sources': {'runtime_patchset_sha256': 'old'}}, destination, dict(os.environ), 2)
            manifest = json.loads((destination / 'build.json').read_text())
            return code, manifest, run.call_count

    def test_command_failure_stops_before_target_builds(self):
        code, manifest, calls = self.run_fixture(returncode=7)
        self.assertEqual((code, calls), (2, 1))
        self.assertEqual(manifest['state'], 'failed')
        self.assertEqual(manifest['steps'][0]['returncode'], 7)

    def test_success_exit_without_artifacts_is_failure(self):
        code, manifest, calls = self.run_fixture(create_outputs=False)
        self.assertEqual((code, calls), (2, 2))
        self.assertIn('Missing or empty', manifest['error'])

    def test_artifact_escape_is_failure(self):
        code, manifest, _ = self.run_fixture(escaping=True)
        self.assertEqual(code, 2)
        self.assertIn('escapes', manifest['error'])

    def test_compilation_does_not_mark_m0_or_runtime_complete(self):
        code, manifest, calls = self.run_fixture()
        self.assertEqual((code, calls), (0, 6))
        self.assertEqual(manifest['state'], 'compiled-not-device-validated')
        self.assertFalse(manifest['m0_passed'])
        self.assertFalse(manifest['runtime_implemented'])
        self.assertEqual(len(manifest['artifacts']), 8)


if __name__ == '__main__':
    unittest.main()
