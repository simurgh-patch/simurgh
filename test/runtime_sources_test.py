"""Source patch provenance must fail closed and preserve unexpected edits."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from runtime_sources import verify_runtime_sources


class RuntimeSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='runtime-source-', dir=ROOT / 'output')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        self.patches = self.root / 'patches'
        self.patches.mkdir()
        self.run_git('init', '-q')
        (self.source / 'runtime.cc').write_text('original\n')
        (self.source / 'other.cc').write_text('preserve\n')
        self.run_git('add', '.')
        self.run_git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'test fixture')
        revision = self.run_git('rev-parse', 'HEAD').decode().strip()
        (self.source / 'runtime.cc').write_text('patched\n')
        patch = self.run_git('diff')
        (self.patches / 'fix.patch').write_bytes(patch)
        (self.source / 'runtime.cc').write_text('original\n')
        digest = lambda value: hashlib.sha256(value).hexdigest()
        self.manifest = {'schema': 1, 'dart_revision': revision, 'patches': [
            {'path': 'fix.patch', 'sha256': digest(patch), 'files': {
                'runtime.cc': {'base_sha256': digest(b'original\n'), 'patched_sha256': digest(b'patched\n')}}}]}
        self.save()

    def run_git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.source, stderr=subprocess.STDOUT)

    def save(self):
        (self.patches / 'manifest.json').write_text(json.dumps(self.manifest))

    def verify(self, apply=False):
        return verify_runtime_sources(self.source, self.patches, apply=apply)

    def test_clean_application_and_idempotent_verification(self):
        with self.assertRaisesRegex(ValueError, 'not applied'):
            self.verify()
        result = self.verify(apply=True)
        self.assertEqual((self.source / 'runtime.cc').read_text(), 'patched\n')
        self.assertEqual(self.verify(), result)
        self.assertEqual(self.verify(apply=True), result)
        self.assertEqual((self.source / 'other.cc').read_text(), 'preserve\n')

    def test_unrecorded_edit_is_preserved(self):
        (self.source / 'other.cc').write_text('user work\n')
        with self.assertRaisesRegex(ValueError, 'Unrecorded'):
            self.verify(apply=True)
        self.assertEqual((self.source / 'other.cc').read_text(), 'user work\n')
        self.assertEqual((self.source / 'runtime.cc').read_text(), 'original\n')

    def test_conflicting_edit_is_preserved(self):
        (self.source / 'runtime.cc').write_text('user work\n')
        with self.assertRaisesRegex(ValueError, 'differs from both'):
            self.verify(apply=True)
        self.assertEqual((self.source / 'runtime.cc').read_text(), 'user work\n')

    def test_patch_tamper_rejected_before_mutation(self):
        (self.patches / 'fix.patch').write_text('modified patch')
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.verify(apply=True)
        self.assertEqual((self.source / 'runtime.cc').read_text(), 'original\n')

    def test_wrong_revision_and_path_escape_rejected(self):
        self.manifest['dart_revision'] = '0' * 40
        self.save()
        with self.assertRaisesRegex(ValueError, 'different Dart revision'):
            self.verify(apply=True)
        self.manifest['dart_revision'] = self.run_git('rev-parse', 'HEAD').decode().strip()
        self.manifest['patches'][0]['path'] = '../outside.patch'
        self.save()
        with self.assertRaisesRegex(ValueError, 'escapes source root'):
            self.verify(apply=True)
