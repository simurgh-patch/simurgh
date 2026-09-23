import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('prepare_engine', ROOT / 'scripts/prepare_engine.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PreparationGateTest(unittest.TestCase):
    def setUp(self):
        self.lock = json.loads((ROOT / 'toolchain.lock.json').read_text())

    def test_low_space_never_creates_workspace(self):
        with tempfile.TemporaryDirectory() as parent:
            target = Path(parent) / 'workspace'
            errors = module.check_workspace(target, self.lock, 35 * 1024**3)
            self.assertTrue(errors)
            self.assertFalse(target.exists())

    def test_explicit_override_only_skips_space(self):
        with tempfile.TemporaryDirectory() as parent:
            target = Path(parent) / 'workspace'
            self.assertEqual(module.check_workspace(target, self.lock, 1, True), [])
            target.mkdir()
            (target / 'keep').write_text('keep')
            self.assertTrue(module.check_workspace(target, self.lock, 1, True))

    def test_existing_content_is_preserved(self):
        with tempfile.TemporaryDirectory() as parent:
            target = Path(parent)
            file = target / 'user-file'
            file.write_text('keep')
            self.assertTrue(module.check_workspace(target, self.lock, 250 * 1024**3))
            self.assertEqual(file.read_text(), 'keep')

    def test_valid_empty_workspace_and_exact_budget(self):
        with tempfile.TemporaryDirectory() as parent:
            self.assertEqual(module.check_workspace(Path(parent), self.lock, 200 * 1024**3), [])

    def test_budget_cannot_be_lowered(self):
        self.lock['engine_workspace_min_free_bytes'] = 1
        with tempfile.TemporaryDirectory() as parent:
            self.assertTrue(module.check_workspace(Path(parent), self.lock, 250 * 1024**3))


if __name__ == '__main__':
    unittest.main()
