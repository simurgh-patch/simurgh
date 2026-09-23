"""Safety and provenance tests for source inventories; no engine build."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('source_inventory', ROOT / 'scripts/source_inventory.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SourceInventoryTest(unittest.TestCase):
    def test_entries_are_literals_never_executed(self):
        self.assertEqual(module.parse_entries("entries = {'.': 'https://example.test/repo'}"),
                         {'.': 'https://example.test/repo'})
        for text in ['entries = dict()', 'import os\nentries = {}', 'entries = {1: 2}']:
            with self.assertRaises((ValueError, TypeError)):
                module.parse_entries(text)

    def test_parent_and_symlink_escape_rejected(self):
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / 'root'
            root.mkdir()
            (root / 'escape').symlink_to(parent)
            for name in ['../secret', 'escape/secret', str(Path(parent) / 'secret')]:
                with self.assertRaises(ValueError):
                    module.inside(root, name)

    def test_candidate_names_do_not_claim_license_classification(self):
        for name in ['LICENSE', 'third_party/COPYING.LESSER', 'NOTICE.txt', 'LICENSE-MIT']:
            self.assertTrue(module.license_candidate(name))
        for name in ['src/licensed_code.cc', 'not_a_license.txt', 'README.md']:
            self.assertFalse(module.license_candidate(name))

    def test_annotated_tag_is_compared_to_its_commit(self):
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent)
            def git(path, *args):
                if '--show-toplevel' in args:
                    return str(root)
                if 'HEAD' in args or args[-1].endswith('^{commit}'):
                    return 'a' * 40
                return ''
            with patch.object(module, 'git', side_effect=git), \
                 patch.object(module.subprocess, 'check_output', return_value=b''):
                result = module.repository_inventory(root, 'b' * 40)
            self.assertEqual(result['errors'], [])
            self.assertEqual(result['expected_revision'], 'b' * 40)
            self.assertEqual(result['expected_commit'], 'a' * 40)

    def test_records_dirty_and_wrong_revision_instead_of_certifying(self):
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent)
            (root / 'LICENSE').write_text('synthetic license candidate')
            def git(path, *args):
                if '--show-toplevel' in args:
                    return str(root)
                if args[-1].endswith('^{commit}'):
                    return 'b' * 40
                if 'HEAD' in args:
                    return 'a' * 40
                return ' M LICENSE'
            with patch.object(module, 'git', side_effect=git), \
                 patch.object(module.subprocess, 'check_output', return_value=b'LICENSE\0'):
                result = module.repository_inventory(root, 'b' * 40)
            self.assertIn('revision_mismatch', result['errors'])
            self.assertIn('dirty_checkout', result['errors'])
            self.assertEqual(result['license_review'], 'manual_review_required')
            self.assertEqual(len(result['license_candidates'][0]['sha256']), 64)


if __name__ == '__main__':
    unittest.main()
