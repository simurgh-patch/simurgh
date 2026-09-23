"""Boundary checks against the actual pinned Dart AST transformer (not mocks)."""
import json
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DART = ROOT / '.engine-workspace/engine/engine/src/out/host_release_arm64/dart-sdk/bin/dart'
TOOL = ROOT / 'compiler/bin/aot_patch.dart'
CONFIG = ROOT / 'compiler/.dart_tool/package_config.json'


@unittest.skipUnless(DART.exists() and CONFIG.exists(), 'Pinned source SDK/compiler configuration not prepared')
class AotCompilerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='aot-compiler-', dir=ROOT / 'output')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def command(self, *args):
        return subprocess.run([str(DART), str(TOOL), *map(str, args)], cwd=ROOT, capture_output=True, text=True)

    def source(self, name, content):
        path = self.root / name
        path.write_text(content)
        return path

    def original_source(self, base):
        return json.loads((base / 'source_graph.json').read_text())['libraries']['app:entry']['source']

    def symbol(self, manifest, name, library='app:entry'):
        return next(key for key, value in manifest['entities'].items()
                    if value['name'] == name and value['library'] == library)

    def names(self, manifest, symbols):
        return sorted(manifest['entities'][symbol]['name'] for symbol in symbols)

    def baseline(self):
        base = self.root / 'baseline'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        return base

    def test_original_class_names_keep_distinct_link_identities(self):
        base = self.root / 'type-names'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_type_names_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((base / 'manifest.json').read_text())
        classes = [(symbol, entity) for symbol, entity in manifest['entities'].items()
                   if entity.get('kind') == 'class']
        for symbol, entity in classes:
            self.assertRegex(symbol, r'^msbEntity_class_[0-9a-f]{64}__' + entity['name'] + '$')
        hidden = [symbol for symbol, entity in classes if entity['name'] == '_Hidden']
        self.assertEqual(len(hidden), 2)
        self.assertNotEqual(*hidden)

    def test_rejects_layout_generic_async_and_shadowing_cases(self):
        cases = {
            'generic_class_bound': 'class C<T extends Iterable<(int, int)>> { int value = 1; } void main() {}',
            'generic_bound': 'T f<T extends Iterable<(int, int)>>(T x) => x; void main() {}',
            'async_void': 'void main() async {}',
            'import': "import 'dart:io'; void main() {}",
            'generator_closure': 'void main() { final g = () async* { yield 1; }; g(); }',
            'member': 'int f() => 1; void main() { print(1.f); }',
        }
        for name, source in cases.items():
            with self.subTest(name=name):
                result = self.command('baseline', self.source(name + '.dart', source), self.root / name)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertFalse((self.root / name / 'app.dart').exists())

    def copy_configured_fixture(self, source, target):
        # These tests intentionally edit the root package configuration. Do not
        # expose a root pubspec to workspace auto-pub tooling that can silently
        # regenerate it; retain dependency manifests for the compiler checks.
        shutil.copytree(source, target, ignore=lambda directory, names: {
            name for name in names if name == '.dart_tool' or
            (Path(directory) == source and name in {'pubspec.yaml', 'pubspec.lock'})
        })

    def package_fixture(self, name, side='baseline'):
        source = ROOT / f'compiler/fixtures/aot_packages_{side}'
        target = self.root / name
        self.copy_configured_fixture(source, target)
        entries = [{'name': folder.name, 'rootUri': '../packages/' + folder.name,
                    'packageUri': 'lib/', 'languageVersion': '3.0'}
                   for folder in sorted((target / 'packages').iterdir())]
        entries.append({'name': 'package_probe', 'rootUri': '../', 'packageUri': 'lib/', 'languageVersion': '3.0'})
        config = target / '.dart_tool/package_config.json'
        config.parent.mkdir()
        config.write_text(json.dumps({'configVersion': 2, 'packages': entries}))
        return target

    def test_package_graph_relocation_upgrade_and_private_names(self):
        first = self.package_fixture('package-first')
        second = self.package_fixture('package-moved')
        candidate = self.package_fixture('package-new', 'patch')
        base = self.root / 'package-base'
        moved = self.root / 'package-moved-base'
        for path, out in [(first, base), (second, moved)]:
            result = self.command('baseline', path / 'app.dart', out)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((base / 'source_graph.json').read_bytes(), (moved / 'source_graph.json').read_bytes())
        graph = json.loads((base / 'source_graph.json').read_text())
        self.assertIn('package:engine_logic/src/logic.dart', graph['libraries'])
        self.assertIn('package:utility/utility.dart', graph['libraries'])
        self.assertEqual(graph['language_version'], '3.0')
        self.assertTrue((base / 'app.dart').read_text().startswith('// @dart=3.0'))
        private = [symbol for symbol, record in graph['entities'].items() if record['name'] == '_secret']
        self.assertEqual(len(private), 2)
        patch = self.root / 'package-output'
        result = self.command('patch', candidate / 'app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        metadata = json.loads((patch / 'manifest.json').read_text())
        self.assertNotIn('main', self.names(metadata, metadata['changed_functions']))
        self.assertIn('decorate', self.names(metadata, metadata['added_functions']))
        self.assertTrue((patch / 'module.dart').read_text().startswith('// @dart=3.0'))

    def test_package_resolution_and_native_inputs_fail_closed(self):
        for case in ['missing', 'symlink', 'native']:
            with self.subTest(case=case):
                fixture = self.package_fixture('package-' + case)
                config = fixture / '.dart_tool/package_config.json'
                data = json.loads(config.read_text())
                if case == 'missing':
                    data['packages'] = [p for p in data['packages'] if p['name'] != 'utility']
                    config.write_text(json.dumps(data))
                elif case == 'native':
                    hook = fixture / 'packages/utility/hook/build.dart'
                    hook.parent.mkdir()
                    hook.write_text('void main() {}')
                else:
                    outside = self.source('escaped-package.dart', 'int escaped() => 1;')
                    link = fixture / 'packages/utility/lib/leak.dart'
                    link.symlink_to(outside)
                    (fixture / 'packages/utility/lib/utility.dart').write_text("export 'leak.dart'; int adjust(int n) => n;")
                output = self.root / ('rejected-' + case)
                result = self.command('baseline', fixture / 'app.dart', output)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertFalse((output / 'app.dart').exists())
                expected = {'missing': 'Unresolved local package', 'symlink': 'escapes',
                            'native': 'Native plugin or build hook'}[case]
                self.assertIn(expected, result.stderr)

    def test_mixed_language_declarations_are_emitted_per_origin_library(self):
        base = self.root / 'mixed-base'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_multilang_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((base / 'manifest.json').read_text())
        self.assertEqual(set(manifest['library_language_versions'].values()), {'3.0', '3.12'})
        self.assertEqual(len(set(manifest['emitted_libraries'].values())), 3)
        for uri, filename in manifest['emitted_libraries'].items():
            self.assertTrue((base / filename).read_text().startswith('// @dart=' + manifest['library_language_versions'][uri]))
        legacy = (base / manifest['emitted_libraries']['app:legacy.dart']).read_text()
        self.assertIn('int msbEntity_ignored_0', legacy)
        self.assertIn('legacyLocal(msbEntity_ignored_0)', legacy)
        self.assertIn('var _ = 2', legacy)
        interface = (base / 'dynamic_interface.yaml').read_text()
        self.assertIn(manifest['emitted_libraries']['app:legacy.dart'], interface)
        patch = self.root / 'mixed-patch'
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_multilang_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((patch / manifest['emitted_libraries']['app:legacy.dart']).read_text().startswith('// @dart=3.0'))

    def test_new_library_may_have_different_language_without_changing_old_ones(self):
        base = self.root / 'added-language-base'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_multilang_added_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        patch = self.root / 'added-language-patch'
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_multilang_added_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        graph = json.loads((patch / 'source_graph.json').read_text())
        self.assertEqual(graph['library_language_versions']['app:entry'], '3.0')
        self.assertEqual(graph['library_language_versions']['app:modern.dart'], '3.12')
        self.assertEqual(len(list(patch.glob('unit_*.dart'))), 2)

    def test_package_language_change_requires_new_baseline(self):
        fixture = self.package_fixture('language-change')
        base = self.root / 'language-base'
        result = self.command('baseline', fixture / 'app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        config = fixture / '.dart_tool/package_config.json'
        data = json.loads(config.read_text())
        for package in data['packages']:
            package['languageVersion'] = '3.12'
        config.write_text(json.dumps(data))
        result = self.command('patch', fixture / 'app.dart', base, self.root / 'language-patch')
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn('Language version changes require a new baseline', result.stderr)

    def test_sdk_types_and_imports_resolve_to_canonical_entities(self):
        base = self.root / 'sdk-base'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_sdk_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        source = (base / 'source.dart').read_text()
        self.assertIn('msbEntity_sdk_typed_data.Uint8List', source)
        self.assertIn('msbEntity_sdk_math.max', source)
        self.assertIn('msbEntity_sdk_collection.Queue', source)
        patch = self.root / 'sdk-patch'
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_sdk_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        changed = json.loads((patch / 'manifest.json').read_text())
        self.assertNotIn('stableRead', self.names(changed, changed['changed_functions']))
        self.assertNotIn('main', self.names(changed, changed['changed_functions']))
        self.assertIn('dart:convert', (base / 'dynamic_interface.yaml').read_text())

    def test_sdk_reexport_prefix_and_hide_preserve_resolution(self):
        self.source('api.dart', "export 'dart:math' show max;\n")
        source = self.source('sdk-export.dart', "import 'api.dart' as math; num f() => math.max(1, 2); void main() { print(f()); }")
        base = self.root / 'sdk-export-base'
        result = self.command('baseline', source, base)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('msbEntity_sdk_math.max(1, 2)', (base / 'source.dart').read_text())
        hidden = self.source('sdk-hide.dart', "import 'dart:math' hide max; void main() { max(1, 2); }")
        result = self.command('baseline', hidden, self.root / 'sdk-hidden')
        self.assertEqual(result.returncode, 2)
        self.assertIn('Static source errors', result.stderr)

    def test_dynamic_contract_is_bound_to_baseline(self):
        import hashlib
        base = self.baseline()
        manifest = json.loads((base / 'manifest.json').read_text())
        contract = base / 'dynamic_interface.yaml'
        self.assertEqual(manifest['dynamic_interface_sha256'], hashlib.sha256(contract.read_bytes()).hexdigest())
        self.assertIn('invoke:unary-', manifest['dynamic_selectors'])
        contract.write_text(contract.read_text() + '  - "invoke:unreviewed"\n')
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_patch/app.dart', base, self.root / 'tampered')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'tampered/module.dart').exists())

    def test_globals_dependency_closure_and_shared_state(self):
        base = self.root / 'globals-base'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_globals_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        patch = self.root / 'globals-patch'
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_globals_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['replaced_globals']), ['derived', 'held', 'initialized', 'seed'])
        self.assertNotIn('readShared', self.names(manifest, manifest['changed_functions']))
        self.assertIn('withDefault', self.names(manifest, manifest['module_only_functions']))
        self.assertIn('readValue', self.names(manifest, manifest['installed_functions']))
        self.assertNotIn('withDefault', self.names(manifest, manifest['installed_functions']))
        module = (patch / 'module.dart').read_text()
        self.assertIn('simurghBaseline.' + self.symbol(manifest, 'shared'), module)

    def test_resolved_function_method_and_callback_signatures(self):
        base = self.root / 'signatures-base'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_signatures_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((base / 'manifest.json').read_text())
        calculate = self.symbol(manifest, 'calculate')
        self.assertTrue(manifest['functions'][calculate]['signature'].startswith('dynamic '))
        self.assertIn('(dynamic value)', manifest['functions'][calculate]['signature'])
        echo = self.symbol(manifest, 'Child.echo')
        self.assertTrue(manifest['functions'][echo]['signature'].startswith('msbEntity_type_'))
        self.assertIn('(int value)', (base / 'source.dart').read_text())
        patch = self.root / 'signatures-patch'
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_signatures_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        changed = json.loads((patch / 'manifest.json').read_text())
        self.assertIn('loop', self.names(changed, changed['installed_functions']))
        self.assertNotIn('calculate', self.names(changed, changed['changed_functions']))
        self.assertIn('forward', self.names(changed, changed['installed_functions']))

    def test_inferred_dynamic_signature_cannot_silently_narrow(self):
        source = self.source('inferred-api.dart', 'function(value) => value; main() { function(1); }')
        base = self.root / 'inferred-api-base'
        result = self.command('baseline', source, base)
        self.assertEqual(result.returncode, 0, result.stderr)
        source.write_text('int function(int value) => value; main() { function(1); }')
        result = self.command('patch', source, base, self.root / 'inferred-api-patch')
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn('Signature changed', result.stderr)

    def test_inferred_globals_fields_and_generic_callbacks(self):
        base = self.root / 'inference-base'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_inference_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        patch = self.root / 'inference-patch'
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_inference_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['replaced_globals']), ['changed', 'held', 'increment'])
        self.assertNotIn('stableRead', self.names(manifest, manifest['changed_functions']))
        self.assertNotIn('viaStored', self.names(manifest, manifest['changed_functions']))
        entities = manifest['entities']
        self.assertEqual(entities[self.symbol(manifest, 'changed')]['inferred_type'], 'String')
        self.assertEqual(entities[self.symbol(manifest, 'callback')]['inferred_type'], 'int Function(int)')
        self.assertEqual(entities[self.symbol(manifest, 'choose')]['inferred_type'], 'T Function<T>(T, T)')
        self.assertIn('defaultArg', self.names(manifest, manifest['module_only_functions']))

    def test_inference_does_not_drop_metadata_or_external_boundary(self):
        for index, source in enumerate([
            "@deprecated final value = 1; void main() {}",
            'external int value; void main() {}',
        ]):
            result = self.command('baseline', self.source(f'inference-invalid-{index}.dart', source), self.root / f'inference-invalid-{index}')
            self.assertEqual(result.returncode, 2, result.stdout)

    def test_late_final_uses_shared_baseline_storage(self):
        base = self.root / 'late-final-base'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_late_final_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        patch = self.root / 'late-final-patch'
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_late_final_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(manifest['replaced_globals'], [])
        self.assertNotIn('readShared', self.names(manifest, manifest['changed_functions']))
        self.assertNotIn('writeFromAot', self.names(manifest, manifest['changed_functions']))
        module = (patch / 'module.dart').read_text()
        self.assertIn('simurghBaseline.' + self.symbol(manifest, 'shared'), module)
        self.assertIn('simurghBaseline.' + self.symbol(manifest, 'newlyWritten'), module)

    def test_globals_unsupported_and_deletion_rejected(self):
        for index, source in enumerate(['var value = (1, 2); void main() {}']):
            result = self.command('baseline', self.source(f'bad-global-{index}.dart', source), self.root / f'bad-global-{index}')
            self.assertEqual(result.returncode, 2, result.stdout)
        source = self.source('global.dart', 'int value = 1; void main() {}')
        base = self.root / 'global-base'
        self.assertEqual(self.command('baseline', source, base).returncode, 0)
        source.write_text('void main() {}')
        result = self.command('patch', source, base, self.root / 'global-patch')
        self.assertEqual(result.returncode, 2)
        self.assertIn('Deleted globals', result.stderr)

    def test_prefixed_private_and_grouped_globals(self):
        entry = self.source('app.dart', "import 'state.dart' as s; void main() { s.value++; print(s.read()); }")
        state = self.source('state.dart', 'int value = 1, other = 2; int _secret = 8; int read() => value + other + _secret;')
        base = self.root / 'multi-base'
        result = self.command('baseline', entry, base)
        self.assertEqual(result.returncode, 0, result.stderr)
        state.write_text(state.read_text().replace('value = 1', 'value = 3'))
        patch = self.root / 'multi-patch'
        result = self.command('patch', entry, base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['replaced_globals']), ['other', 'value'])
        self.assertNotIn('_secret', self.names(manifest, manifest['replaced_globals']))

    def test_signature_change_is_not_emitted_as_patch(self):
        base = self.baseline()
        source = self.original_source(base).replace('int calculate(int value)', 'int calculate(int value, int extra)').replace('calculate(value)', 'calculate(value, 0)').replace('calculate(100)', 'calculate(100, 0)')
        result = self.command('patch', self.source('candidate.dart', source), base, self.root / 'patch')
        self.assertEqual(result.returncode, 2)
        self.assertIn('Signature changed', result.stderr)
        self.assertFalse((self.root / 'patch/module.dart').exists())

    def test_new_class_addition_is_emitted(self):
        base = self.baseline()
        source = self.original_source(base) + '\nclass NewClass {}\n'
        result = self.command('patch', self.source('candidate.dart', source), base, self.root / 'patch')
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.root / 'patch/manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['NewClass'])
        self.assertEqual(manifest['changed_functions'], [])
        self.assertIn('class ' + self.symbol(manifest, 'NewClass'), (self.root / 'patch/module.dart').read_text())

    def test_baseline_fingerprint_tampering_is_rejected(self):
        base = self.baseline()
        manifest = json.loads((base / 'manifest.json').read_text())
        manifest['baseline_fingerprint'] = '0' * 64
        (base / 'manifest.json').write_text(json.dumps(manifest))
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_patch/app.dart', base, self.root / 'patch')
        self.assertEqual(result.returncode, 2)
        self.assertIn('fingerprint mismatch', result.stderr)

    def test_comment_only_change_has_no_patch(self):
        base = self.baseline()
        source = '// comment only\n' + self.original_source(base)
        result = self.command('patch', self.source('candidate.dart', source), base, self.root / 'patch')
        self.assertEqual(result.returncode, 2)
        self.assertIn('No function body changes', result.stderr)

    def test_existing_output_is_preserved(self):
        base = self.baseline()
        original = (base / 'app.dart').read_bytes()
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_baseline/app.dart', base)
        self.assertEqual(result.returncode, 2)
        self.assertEqual((base / 'app.dart').read_bytes(), original)

    def test_patch_contains_only_changed_functions(self):
        base = self.baseline()
        patch = self.root / 'patch'
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['changed_functions']), ['calculate', 'fail'])
        # Bytecode-to-AOT calls stay references to the retained baseline.
        source = (patch / 'module.dart').read_text()
        self.assertIn(f"simurghBaseline.{self.symbol(manifest, 'unchanged')}(value)", source)
        self.assertNotIn(f"simurghPatch_{self.symbol(manifest, 'unchanged')}", source)
        self.assertFalse(manifest['production_patch'])

    def test_added_functions_and_rebound_callers(self):
        base = self.root / 'baseline'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_entities_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        patch = self.root / 'patch'
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_entities_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['added_functions']), ['addition', 'identical', 'recurse'])
        self.assertEqual(self.names(manifest, manifest['changed_functions']), ['calculate', 'main'])
        self.assertEqual(self.names(manifest, manifest['rebound_callers']['main']), ['identical'])
        # Retained callable values use AOT entries; new recursion stays in module.
        self.assertEqual(manifest['module_entities'][self.symbol(manifest, 'calculate')]['references'][self.symbol(manifest, 'unchanged')], 'baseline-entry')
        self.assertEqual(manifest['module_entities'][self.symbol(manifest, 'recurse')]['references'][self.symbol(manifest, 'addition')], 'module-function')
        source = (patch / 'module.dart').read_text()
        self.assertIn(f"final retained = simurghBaseline.{self.symbol(manifest, 'unchanged')};", source)
        self.assertIn(f"simurghPatch_{self.symbol(manifest, 'recurse')}(value - 1)", source)
        self.assertNotIn(f"\"{self.symbol(manifest, 'addition')}\": simurghPatch_", source)

    def test_deleted_function_is_rejected(self):
        base = self.baseline()
        source = self.original_source(base).replace('int caller(int value) => calculate(value) + 1;', '')
        source = '\n'.join(line for line in source.splitlines() if "print('caller=" not in line)
        result = self.command('patch', self.source('deleted.dart', source), base, self.root / 'patch')
        self.assertEqual(result.returncode, 2)
        self.assertIn('Deleted functions', result.stderr)

    def test_resolved_local_binding_survives_new_same_named_function(self):
        base = self.baseline()
        source = self.original_source(base) + '\nint error() => 1;\n'
        result = self.command('patch', self.source('shadow.dart', source), base, self.root / 'patch')
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.root / 'patch/manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['added_functions']), ['error'])
        self.assertEqual(manifest['changed_functions'], [])

    def test_closures_keep_unchanged_callback_consumers_in_aot(self):
        base = self.root / 'baseline'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_closures_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        patch = self.root / 'patch'
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_closures_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['changed_functions']), ['makeCounter', 'makeFailure'])
        self.assertEqual(manifest['added_functions'], [])
        self.assertIn(f"simurghBaseline.{self.symbol(manifest, 'unchanged')}(count)", (patch / 'module.dart').read_text())

    def test_static_errors_rejected_before_emitting_artifacts(self):
        cases = [
            'int f(int x) => x; void main() { print(f("wrong type")); }',
            'void main() { missingFunction(); }',
            'int String(int x) => x; void main() { final String x = "bad binding"; print(x); }',
        ]
        for index, source in enumerate(cases):
            with self.subTest(index=index):
                output = self.root / f'invalid-{index}'
                result = self.command('baseline', self.source(f'invalid-{index}.dart', source), output)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertIn('Static source errors', result.stderr)
                self.assertFalse(output.exists())

    def test_library_identity_and_export_rebinding(self):
        base, patch = self.root / 'baseline', self.root / 'patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_libraries_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_libraries_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        changed = {(manifest['entities'][s]['library'], manifest['entities'][s]['name'])
                   for s in manifest['changed_functions']}
        self.assertEqual(changed, {('app:entry', 'main'), ('app:left.dart', '_offset'), ('app:left.dart', 'evaluate')})
        self.assertEqual(self.names(manifest, manifest['added_functions']), ['extra'])
        left = self.symbol(manifest, '_offset', 'app:left.dart')
        right = self.symbol(manifest, '_offset', 'app:right.dart')
        self.assertNotEqual(left, right)
        self.assertNotIn(right, manifest['changed_functions'])
        # Import order and checkout location cannot change entity identity.
        copied = self.root / 'copied'
        shutil.copytree(ROOT / 'compiler/fixtures/aot_libraries_baseline', copied)
        copied_base = self.root / 'copied-base'
        result = self.command('baseline', copied / 'app.dart', copied_base)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((base / 'manifest.json').read_text())['baseline_fingerprint'],
                         json.loads((copied_base / 'manifest.json').read_text())['baseline_fingerprint'])

    def test_original_library_privacy_and_ambiguity_are_enforced(self):
        cases = {
            'private': ("import 'lib.dart' as dep; void main() { print(dep._hidden()); }",
                        'int _hidden() => 1;'),
            'hidden': ("import 'lib.dart' hide exposed; void main() { print(exposed()); }",
                       'int exposed() => 1;'),
        }
        for name, (entry, dependency) in cases.items():
            with self.subTest(name=name):
                folder = self.root / name
                folder.mkdir()
                (folder / 'app.dart').write_text(entry)
                (folder / 'lib.dart').write_text(dependency)
                output = self.root / (name + '-output')
                result = self.command('baseline', folder / 'app.dart', output)
                self.assertEqual(result.returncode, 2)
                self.assertIn('Static source errors', result.stderr)
                self.assertFalse(output.exists())

    def test_source_graph_tampering_is_rejected(self):
        base = self.baseline()
        graph = json.loads((base / 'source_graph.json').read_text())
        graph['libraries']['app:entry']['source'] += '\n// changed archive\n'
        (base / 'source_graph.json').write_text(json.dumps(graph))
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_patch/app.dart', base, self.root / 'patch')
        self.assertEqual(result.returncode, 2)
        self.assertIn('fingerprint mismatch', result.stderr)

    def test_source_root_escape_and_deferred_import_are_rejected(self):
        (self.root / 'outside.dart').write_text('int outside() => 1;')
        folder = self.root / 'nested'
        folder.mkdir()
        (folder / 'lib.dart').write_text('int exposed() => 1;')
        for index, source in enumerate([
            "import '../outside.dart'; void main() {}",
            "import 'lib.dart' deferred as dep; void main() {}",
        ]):
            (folder / 'app.dart').write_text(source)
            result = self.command('baseline', folder / 'app.dart', self.root / f'unsupported-{index}')
            self.assertEqual(result.returncode, 2)
            self.assertIn('source root' if index == 0 else 'deferred', result.stderr)

    def test_instance_methods_keep_baseline_classes_and_unchanged_callers(self):
        base, patch = self.root / 'baseline', self.root / 'patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_classes_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_classes_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['changed_functions']),
                         ['Base._adjust', 'Base.assignmentForms', 'Base.callback', 'Base.fail', 'Child.compute', 'make'])
        self.assertEqual(manifest['added_functions'], [])
        baseline_manifest = json.loads((base / 'manifest.json').read_text())
        self.assertEqual(len(baseline_manifest['class_shapes']), 2)
        self.assertNotIn('class ', (patch / 'module.dart').read_text())
        for name in ['invoke', 'main', 'caught']:
            self.assertNotIn(self.symbol(manifest, name), manifest['changed_functions'])

    def test_layout_closure_rebinds_fields_returns_defaults_and_closed_ancestors(self):
        base, patch = self.root / 'baseline', self.root / 'patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_layout_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_layout_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['replaced_classes']), ['Box', 'Child', 'Holder', 'Locked', 'LockedChild', 'Worker'])
        self.assertEqual(self.names(manifest, manifest['installed_functions']), ['fromDefault', 'isBox', 'main'])
        self.assertIn(self.symbol(manifest, 'defaultFactory'), manifest['module_only_functions'])
        self.assertIn(self.symbol(manifest, 'factory'), manifest['module_only_functions'])
        for name in ['stable', 'invokeBase', 'check', 'churn', 'Base.hook']:
            self.assertNotIn(self.symbol(manifest, name), manifest['changed_functions'])
        original = json.loads((base / 'manifest.json').read_text())
        self.assertEqual(self.names(original, manifest['retired_functions']), ['Box.obsolete'])
        self.assertFalse(set(manifest['module_only_functions']) & set(manifest['installed_functions']))

    def test_generic_classes_preserve_receiver_types_and_substitute_super(self):
        base, patch = self.root / 'baseline', self.root / 'patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_generic_classes_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_generic_classes_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['changed_functions']),
                         ['Box.later', 'Box.pick', 'Box.shadow', 'Box.typeName', 'make'])
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['Added'])
        for name in ['main', 'read', 'covariance', 'churn', 'IntBox.pick', 'Child.pick']:
            self.assertNotIn(self.symbol(manifest, name), manifest['changed_functions'])
        self.assertIn('msbEntity_type_', (base / 'app.dart').read_text())

    def test_generic_class_bounds_and_arity_create_new_versions(self):
        source = 'class Box<T extends num> { T value; Box(this.value); T read() => value; } void main() {}'
        base = self.root / 'baseline'
        result = self.command('baseline', self.source('base.dart', source), base)
        self.assertEqual(result.returncode, 0, result.stderr)
        for index, candidate in enumerate([
            source.replace('T extends num', 'T'),
            source.replace('T extends num', 'T extends num, U'),
        ]):
            result = self.command('patch', self.source('candidate.dart', candidate), base, self.root / f'patch-{index}')
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((self.root / f'patch-{index}' / 'manifest.json').read_text())
            self.assertTrue(manifest['replaced_classes'])
            self.assertFalse(set(manifest['module_only_functions']) & set(manifest['installed_functions']))

    def test_generic_functions_methods_closures_and_tearoffs(self):
        base, patch = self.root / 'baseline', self.root / 'patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_generics_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_generics_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['changed_functions']),
                         ['Selector.pick', 'bounded', 'capture', 'choose', 'later', 'make', 'typed'])
        for name in ['main', 'relay', 'invoke', 'Child.pick', 'throughClass', 'checkBound']:
            self.assertNotIn(self.symbol(manifest, name), manifest['changed_functions'])
        self.assertIn('Function<T>', (base / 'app.dart').read_text())
        self.assertIn('Replacement<T>', (base / 'app.dart').read_text())

    def test_generic_bounds_and_arity_changes_are_rejected(self):
        original = 'T value<T extends num>(T first) => first; void main() { print(value<int>(1)); }'
        base = self.root / 'baseline'
        result = self.command('baseline', self.source('base.dart', original), base)
        self.assertEqual(result.returncode, 0, result.stderr)
        for index, candidate in enumerate([
            original.replace('T extends num', 'T'),
            original.replace('T extends num', 'T extends num, U').replace('value<int>', 'value<int, int>'),
        ]):
            result = self.command('patch', self.source('candidate.dart', candidate), base, self.root / f'patch-{index}')
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertIn('Signature changed', result.stderr)

    def test_async_declarations_closures_and_methods_preserve_sync_dispatch(self):
        base, patch = self.root / 'baseline', self.root / 'patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_async_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_async_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['changed_functions']),
                         ['Box.step', 'arrow', 'calculate', 'fail', 'make', 'ordered', 'passthrough', 'widened'])
        for name in ['main', 'stable', 'nested', 'churn', 'caught']:
            self.assertNotIn(self.symbol(manifest, name), manifest['changed_functions'])
        self.assertIn('await app.main();', (base / 'launcher.dart').read_text())
        self.assertIn('Future<num> simurghOriginalBody() async', (base / 'app.dart').read_text())
        self.assertIn("library: 'dart:async'", (base / 'dynamic_interface.yaml').read_text())

    def test_future_signature_change_is_rejected(self):
        source = 'Future<int> value() async => 1; Future<void> main() async { await value(); }'
        base = self.root / 'baseline'
        result = self.command('baseline', self.source('base.dart', source), base)
        self.assertEqual(result.returncode, 0, result.stderr)
        candidate = source.replace('Future<int>', 'Future<String>').replace('=> 1', "=> 'value'")
        result = self.command('patch', self.source('patch.dart', candidate), base, self.root / 'patch')
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn('Signature changed', result.stderr)

    def test_optional_named_parameters_and_default_callback_linkage(self):
        base, patch = self.root / 'baseline', self.root / 'patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_parameters_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_parameters_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['changed_functions']), ['Child.compute', 'adjust', 'make', 'optional'])
        for name in ['main', 'consume', 'invoke', 'Base.compute']:
            self.assertNotIn(self.symbol(manifest, name), manifest['changed_functions'])
        self.assertIn('required int bias', (base / 'app.dart').read_text())
        self.assertIn('Function(int, [int])', (base / 'app.dart').read_text())

    def test_parameter_defaults_and_requiredness_changes_rejected(self):
        base = self.root / 'baseline'
        original = (ROOT / 'compiler/fixtures/aot_parameters_baseline/app.dart').read_text()
        result = self.command('baseline', self.source('base.dart', original), base)
        self.assertEqual(result.returncode, 0, result.stderr)
        for index, candidate in enumerate([
            original.replace('[int delta = 3]', '[int delta = 4]'),
            original.replace('required int bias', 'int bias = 0', 1),
        ]):
            result = self.command('patch', self.source('candidate.dart', candidate), base, self.root / f'patch-{index}')
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertIn('Signature changed', result.stderr)

    def test_accessor_slots_are_distinct_and_callers_stay_aot(self):
        base, patch = self.root / 'baseline', self.root / 'patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_accessors_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_accessors_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        changed = [manifest['entities'][symbol] for symbol in manifest['changed_functions']]
        self.assertEqual(sorted(record['kind'] for record in changed), ['instance-getter', 'instance-setter'])
        self.assertEqual([record['name'] for record in changed], ['Base.value', 'Base.value'])
        self.assertEqual(manifest['added_functions'], [])
        for name in ['read', 'write', 'churn', 'main', 'Child.step']:
            self.assertNotIn(self.symbol(manifest, name), manifest['changed_functions'])

    def test_accessor_signature_and_removal_create_new_versions(self):
        base = self.root / 'baseline'
        source = 'class C { int get value => 1; void set value(int x) {} } void main() {}'
        result = self.command('baseline', self.source('base.dart', source), base)
        self.assertEqual(result.returncode, 0, result.stderr)
        for index, candidate in enumerate([
            source.replace('int get value', 'num get value'),
            source.replace('void set value(int x) {}', ''),
        ]):
            result = self.command('patch', self.source('candidate.dart', candidate), base, self.root / f'patch-{index}')
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((self.root / f'patch-{index}' / 'manifest.json').read_text())
            self.assertTrue(manifest['replaced_classes'])
            self.assertFalse(set(manifest['module_only_functions']) & set(manifest['installed_functions']))

    def test_class_layout_constructor_and_member_set_changes_are_relocated(self):
        base = self.root / 'baseline'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_classes_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, old, new in [
            ('layout', 'int _value;', 'int _value; int extra = 0;'),
            ('constructor', 'Base(this._value);', 'Base(this._value) { _value += 1; }'),
            ('method', 'Base self()', 'int extraMethod() => 1; Base self()'),
        ]:
            with self.subTest(name=name):
                candidate = self.root / name
                shutil.copytree(ROOT / 'compiler/fixtures/aot_classes_baseline', candidate)
                source = candidate / 'base.dart'
                source.write_text(source.read_text().replace(old, new))
                output = self.root / (name + '-patch')
                result = self.command('patch', candidate / 'app.dart', base, output)
                self.assertEqual(result.returncode, 0, result.stderr)
                manifest = json.loads((output / 'manifest.json').read_text())
                self.assertEqual(self.names(manifest, manifest['replaced_classes']), ['Base', 'Child'])
                self.assertFalse(set(manifest['module_only_functions']) & set(manifest['installed_functions']))

    def test_parts_share_library_identity_when_declarations_move(self):
        base, patch = self.root / 'parts-base', self.root / 'parts-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_parts_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_parts_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        original = json.loads((base / 'manifest.json').read_text())
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(manifest['replaced_classes'], [])
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['Added'])
        self.assertEqual(self.names(manifest, manifest['changed_functions']), ['_bonus', 'bump', 'callback', 'make'])
        for name in ['Base', '_bonus', 'main']:
            self.assertEqual(self.symbol(original, name), self.symbol(manifest, name))
        graph = json.loads((patch / 'source_graph.json').read_text())
        self.assertEqual(graph['libraries']['app:moved.dart']['owner'], 'app:entry')
        self.assertEqual(graph['libraries']['app:other_part.dart']['owner'], 'app:other.dart')
        self.assertEqual(set(graph['library_language_versions']), {'app:entry', 'app:other.dart'})
        hidden = [key for key, value in manifest['entities'].items() if value['name'] == '_Hidden']
        self.assertEqual(len(hidden), 2)
        self.assertEqual(len(set(hidden)), 2)

    def test_package_parts_keep_owner_language_and_private_identity(self):
        outputs = []
        for side in ['baseline', 'patch']:
            fixture = self.root / ('parts-package-' + side)
            self.copy_configured_fixture(ROOT / ('compiler/fixtures/aot_parts_packages_' + side), fixture)
            config = fixture / '.dart_tool/package_config.json'
            config.parent.mkdir()
            config.write_text(json.dumps({'configVersion': 2, 'packages': [
                {'name': 'piece', 'rootUri': '../packages/piece', 'packageUri': 'lib/', 'languageVersion': '3.0'},
                {'name': 'parts_package_probe', 'rootUri': '../', 'packageUri': 'lib/', 'languageVersion': '3.12'},
            ]}))
            output = self.root / ('parts-package-out-' + side)
            result = self.command('baseline', fixture / 'app.dart', output) if side == 'baseline' else self.command('patch', fixture / 'app.dart', outputs[0], output)
            self.assertEqual(result.returncode, 0, result.stderr)
            outputs.append(output)
        original = json.loads((outputs[0] / 'manifest.json').read_text())
        manifest = json.loads((outputs[1] / 'manifest.json').read_text())
        graph = json.loads((outputs[1] / 'source_graph.json').read_text())
        self.assertEqual(graph['library_language_versions'], {'app:entry': '3.12', 'package:piece/piece.dart': '3.0'})
        self.assertEqual(graph['libraries']['package:piece/src/moved.dart']['owner'], 'package:piece/piece.dart')
        self.assertEqual(self.symbol(original, '_Box', 'package:piece/piece.dart'), self.symbol(manifest, '_Box', 'package:piece/piece.dart'))
        self.assertEqual(manifest['replaced_classes'], [])
        for name in ['main', 'consume']:
            self.assertNotIn(name, self.names(manifest, manifest['changed_functions']))

    def test_parts_reject_invalid_ownership_privacy_versions_and_paths(self):
        cases = {
            'wrong-owner': {'app.dart': "part 'piece.dart'; void main() {}", 'piece.dart': "part of 'other.dart'; int value = 1;", 'other.dart': 'library other;'},
            'missing-part-of': {'app.dart': "part 'piece.dart'; void main() {}", 'piece.dart': 'int value = 1;'},
            'imported-part': {'app.dart': "import 'piece.dart'; void main() {}", 'piece.dart': "part of 'app.dart';"},
            'orphan-entry': {'app.dart': "part of 'other.dart'; void main() {}", 'other.dart': 'library other;'},
            'two-owners': {'app.dart': "import 'left.dart'; import 'right.dart'; void main() {}", 'left.dart': "library shared; part 'piece.dart';", 'right.dart': "library shared; part 'piece.dart';", 'piece.dart': 'part of shared; int value = 1;'},
            'privacy': {'app.dart': "import 'other.dart' as other; part 'piece.dart'; void main() { read(); }", 'piece.dart': "part of 'app.dart'; int read() => other._secret;", 'other.dart': 'int _secret = 1;'},
            'version': {'app.dart': "// @dart=3.0\npart 'piece.dart'; void main() {}", 'piece.dart': "// @dart=3.12\npart of 'app.dart';"},
            'escape': {'app.dart': "part '../escaped.dart'; void main() {}"},
        }
        (self.root / 'escaped.dart').write_text("part of 'escape/app.dart';")
        for name, files in cases.items():
            fixture = self.root / name
            fixture.mkdir()
            for filename, content in files.items():
                (fixture / filename).write_text(content)
            output = self.root / (name + '-out')
            result = self.command('baseline', fixture / 'app.dart', output)
            self.assertEqual(result.returncode, 2, name + ': ' + result.stdout)
            self.assertFalse(output.exists(), name)

    def test_operators_have_distinct_slots_and_retain_aot_consumers(self):
        base, patch = self.root / 'operator-base', self.root / 'operator-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_operators_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_operators_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(manifest['replaced_classes'], [])
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['Added'])
        for name in ['main', 'invoke', 'negative', 'dynamicOps', 'equal', 'churn', 'IndexChild.asyncAdd', 'IndexChild.failed']:
            self.assertNotIn(name, self.names(manifest, manifest['changed_functions']))
        self.assertNotEqual(self.symbol(manifest, 'Num.-'), self.symbol(manifest, 'Num.unary-'))
        for name in ['Num.-', 'Num.unary-', 'Num.+', 'Num.==', 'IndexChild.addedSuper', 'Strings.append']:
            self.assertIn(name, self.names(manifest, manifest['installed_functions']))
        contract = (base / 'dynamic_interface.yaml').read_text()
        for selector in ['invoke:unary-', 'invoke:-', 'invoke:[]', 'invoke:[]=']:
            self.assertIn(selector, contract)

    def test_super_index_adapter_retains_index_parameter_type(self):
        base, patch = self.root / 'operator-check-base', self.root / 'operator-check-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_operator_checks_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_operator_checks_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(manifest['replaced_classes'], [])
        self.assertEqual(self.names(manifest, manifest['changed_functions']), ['Child.index'])
        source = (base / 'app.dart').read_text()
        self.assertIn('<int, int, String, String>', source)

    def test_removing_index_operator_retires_only_generated_adapter(self):
        base, patch = self.root / 'operator-removal-base', self.root / 'operator-removal-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_operator_removal_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_operator_removal_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['replaced_classes']), ['Base', 'Child'])
        original = json.loads((base / 'manifest.json').read_text())
        retired = manifest['retired_infrastructure_classes']
        self.assertEqual(len(retired), 1)
        self.assertEqual(original['entities'][retired[0]]['generated'], 'super-index-cell')

    def test_invalid_operator_signatures_are_rejected_before_emission(self):
        cases = [
            'class C { int operator +(int a, int b) => 1; }',
            'class C { int operator []=(int i, int v) => 1; }',
            'class C { int operator ==(Object other) => 1; }',
            'class C { static int operator +(int a) => 1; }',
        ]
        for index, source in enumerate(cases):
            output = self.root / ('invalid-operator-' + str(index))
            result = self.command('baseline', self.source('invalid-operator-' + str(index) + '.dart', source + ' void main() {}'), output)
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertRegex(result.stderr, 'Static source errors|Invalid Dart source')
            self.assertFalse(output.exists())

    def test_late_fields_keep_storage_and_relink_only_changed_layout(self):
        base, patch = self.root / 'late-field-base', self.root / 'late-field-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_late_fields_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_late_fields_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['replaced_classes']), ['Shape'])
        for name in ['read', 'assign', 'duplicate', 'duplicateOnly', 'uninitialized', 'onlyValue', 'churn']:
            self.assertNotIn(name, self.names(manifest, manifest['changed_functions']))
        self.assertIn('Box.initialize', self.names(manifest, manifest['installed_functions']))
        self.assertIn('setOnly', self.names(manifest, manifest['installed_functions']))
        self.assertIn('shape', self.names(manifest, manifest['module_only_functions']))

    def test_late_fields_preserve_source_assignment_restrictions(self):
        cases = [
            'class C { late final int x = 1; void set() { x = 2; } }',
            'class C { late int x; const C(); }',
            'class C { late const int x = 1; }',
        ]
        for index, source in enumerate(cases):
            output = self.root / ('invalid-late-field-' + str(index))
            result = self.command('baseline', self.source('invalid-late-field-' + str(index) + '.dart', source + ' void main() {}'), output)
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertRegex(result.stderr, 'Static source errors|Invalid Dart source')
            self.assertFalse(output.exists())

    def test_factory_redirects_relink_classes_and_retain_interface_consumers(self):
        base, patch = self.root / 'factory-base', self.root / 'factory-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_factories_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_factories_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['replaced_classes']), ['Cached', 'Choice', 'Original'])
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['Added'])
        for name in ['read', 'build', 'caught', 'churn']:
            self.assertNotIn(name, self.names(manifest, manifest['changed_functions']))
        self.assertNotIn('Box', self.names(manifest, manifest['replaced_classes']))

    def test_invalid_factory_redirects_are_rejected_before_emission(self):
        cases = [
            'class C { factory C() = D; } class D {}',
            'class C { factory C(int x) = C.other; C.other(String x); }',
            'class C { const factory C() = C.other; C.other(); }',
            'class C { factory C() { return this; } }',
        ]
        for index, source in enumerate(cases):
            output = self.root / ('invalid-factory-' + str(index))
            result = self.command('baseline', self.source('invalid-factory-' + str(index) + '.dart', source + ' void main() {}'), output)
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertIn('Static source errors', result.stderr)
            self.assertFalse(output.exists())

    def test_mixins_preserve_aot_consumers_and_relink_layout(self):
        base, patch = self.root / 'mixin-base', self.root / 'mixin-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_mixins_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_mixins_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['replaced_classes']), ['Shape', 'Shaped'])
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['Added', 'Fresh', 'Freshly'])
        for name in ['invoke', 'choose', 'churn']:
            self.assertNotIn(name, self.names(manifest, manifest['changed_functions']))
        for name in ['First.run', 'First.callback', 'Label.label', 'LockedMixin.locked']:
            self.assertIn(name, self.names(manifest, manifest['installed_functions']))
        self.assertIn('shape', self.names(manifest, manifest['module_only_functions']))

    def test_mixin_constraints_and_source_modifiers_are_checked(self):
        cases = [
            'class B {} mixin M on B {} class Wrong with M {}',
            'base mixin M {} class Wrong with M {}',
            'mixin M { M(); }',
            'class C { C(int x); } class Wrong with C {}',
        ]
        for index, source in enumerate(cases):
            result = self.command('baseline', self.source('invalid-mixin-' + str(index) + '.dart', source + ' void main() {}'), self.root / ('invalid-mixin-' + str(index)))
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertRegex(result.stderr, 'Static source errors|Invalid Dart source')

    def test_interfaces_retain_open_consumers_and_relocate_closed_families(self):
        base, patch = self.root / 'interface-base', self.root / 'interface-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_interfaces_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_interfaces_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['replaced_classes']), ['BaseFamily', 'BaseImpl', 'Closed', 'FinalFamily', 'FinalImpl', 'Growing', 'GrowingImpl', 'Variant'])
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['Added', 'BaseOther', 'FinalOther', 'Other'])
        for name in ['read', 'choose', 'update', 'label', 'conforms', 'rejects', 'churn']:
            self.assertNotIn(name, self.names(manifest, manifest['changed_functions']))
        for name in ['readClosed', 'closedTag', 'readGrowing', 'readBase', 'readFinal']:
            self.assertIn(name, self.names(manifest, manifest['module_only_functions']))
            self.assertNotIn(name, self.names(manifest, manifest['installed_functions']))
        baseline = json.loads((base / 'manifest.json').read_text())
        contract = (base / 'dynamic_interface.yaml').read_text()
        for name in ['Value', 'Combined']:
            self.assertIn("class: '" + self.symbol(baseline, name, 'app:contracts.dart') + "'", contract)
        self.assertNotIn("class: '" + self.symbol(baseline, 'Closed') + "'", contract)

    def test_interface_source_restrictions_remain_enforced(self):
        self.source('contracts.dart', 'final class Locked { int read() => 1; }')
        invalid = self.source('invalid-interface.dart', "import 'contracts.dart'; final class Wrong implements Locked { int read() => 2; } void main() {}")
        result = self.command('baseline', invalid, self.root / 'invalid-interface')
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn('Static source errors', result.stderr)
        missing = self.source('missing-interface.dart', 'abstract interface class Port { int read(); } class Missing implements Port {} void main() {}')
        result = self.command('baseline', missing, self.root / 'missing-interface')
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn('Static source errors', result.stderr)
        sdk = self.source('sdk-interface.dart', 'abstract class C implements String {} void main() {}')
        result = self.command('baseline', sdk, self.root / 'sdk-interface')
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn('Static source errors', result.stderr)

    def test_sdk_interfaces_keep_aot_consumers_and_new_sdk_implementations(self):
        base, patch = self.root / 'sdk-interface-base', self.root / 'sdk-interface-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_sdk_interfaces_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_sdk_interfaces_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['AddedRank', 'Numbers', 'Trouble'])
        self.assertEqual(manifest['replaced_classes'], [])
        for name in ['main', 'ordered', 'encoded', 'compare', 'consume', 'caught', 'rejects', 'churn']:
            self.assertNotIn(name, self.names(manifest, manifest['changed_functions']))
            self.assertNotIn(name, self.names(manifest, manifest['module_only_functions']))
        self.assertIn('Rank.compareTo', self.names(manifest, manifest['installed_functions']))
        self.assertIn('TextSink.add', self.names(manifest, manifest['installed_functions']))
        contract = (base / 'dynamic_interface.yaml').read_text().split('extendable:\n')[1]
        for name in ['Comparable', 'Sink', 'Iterator', 'Exception']:
            self.assertIn("class: '" + name + "'", contract)
        for name in ['String', 'int']:
            self.assertNotIn("class: '" + name + "'", contract)

    def test_sdk_interface_and_superclass_source_restrictions(self):
        cases = {
            'base': ("import 'dart:collection'; abstract class C implements LinkedListEntry<C> {} void main() {}", 'Static source errors'),
            'missing': ('class C implements Comparable<C> {} void main() {}', 'Static source errors'),
            'superclass': ('abstract class C extends Comparable<C> {} void main() {}', 'Static source errors'),
            'mixin': ("class C with String {} void main() {}", 'Static source errors'),
            'on': ("import 'dart:collection'; mixin M on ListBase<int> {} class C with M {} void main() {}", 'Static source errors'),
        }
        for name, (source, reason) in cases.items():
            with self.subTest(name=name):
                target = self.root / name
                result = self.command('baseline', self.source(name + '.dart', source), target)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertIn(reason, result.stderr)
                self.assertFalse((target / 'app.dart').exists())

    def test_sdk_mixins_keep_sdk_storage_and_original_aot_consumers(self):
        base, patch = self.root / 'baseline', self.root / 'patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_sdk_mixins_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_sdk_mixins_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['replaced_classes']), [])
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['AddedMap'])
        changed = self.names(manifest, manifest['changed_functions'])
        for name in ['main', 'read', 'joined', 'ordered', 'total', 'churn', 'SDKConstraint.mapped', 'SDKConstraint.replace', 'SDKConstraint.count', 'Compared.comparer', 'MockList.noSuchMethod']:
            self.assertNotIn(name, changed)
            self.assertNotIn(name, self.names(manifest, manifest['module_only_functions']))
        graph = json.loads((base / 'source_graph.json').read_text())
        self.assertIn({'library': 'dart:collection', 'class': 'MapBase'}, graph['sdk_mixins'])
        contracts = (base / 'dynamic_interface.yaml').read_text()
        self.assertIn("class: 'MapBase'", contracts)
        # Constraint-only abstract members must not become eager super calls.
        self.assertIn('StillAbstract', (base / 'app.dart').read_text())

    def test_first_abstract_constraint_super_call_relinks_only_required_classes(self):
        base, patch = self.root / 'baseline', self.root / 'patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_sdk_mixin_relink_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_sdk_mixin_relink_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['replaced_classes']), ['Choosing', 'Chosen'])
        self.assertEqual(self.names(manifest, manifest['added_classes']), [])
        for name in ['main', 'consume', 'Concrete.[]']:
            self.assertNotIn(name, self.names(manifest, manifest['changed_functions']))
            self.assertNotIn(name, self.names(manifest, manifest['module_only_functions']))

    def test_sdk_superclasses_retain_consumers_and_new_sdk_subclasses(self):
        base, patch = self.root / 'sdk-super-base', self.root / 'sdk-super-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_sdk_super_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_sdk_super_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['AddedError', 'FreshMap', 'Node'])
        self.assertEqual(manifest['replaced_classes'], [])
        for name in ['main', 'make', 'sorted', 'mapTotal', 'caught', 'churn', 'Bag.copy', 'Bag.mapped']:
            self.assertNotIn(name, self.names(manifest, manifest['changed_functions']))
            self.assertNotIn(name, self.names(manifest, manifest['module_only_functions']))
        for name in ['Bag.front', 'Bag.render', 'IntBag.[]', 'IntBag.[]=', 'View.step', 'Failure.toString']:
            self.assertIn(name, self.names(manifest, manifest['installed_functions']))
        graph = json.loads((base / 'source_graph.json').read_text())
        self.assertIn({'library': 'dart:collection', 'class': 'LinkedListEntry'}, graph['sdk_superclasses'])
        self.assertNotIn({'library': 'dart:collection', 'class': 'LinkedListEntry'}, graph['sdk_interfaces'])
        contract = (base / 'dynamic_interface.yaml').read_text().split('extendable:\n')[1]
        self.assertIn("class: 'LinkedListEntry'", contract)
        source = (base / 'source.dart').read_text()
        self.assertIn('super.message', source)
        self.assertIn('super.stackTrace', source)
        self.assertRegex(source, r'msbEntity_receiver\.msbEntity_super_[0-9a-f]+<msbEntity_type_')
        self.assertIn('super[', source)

    def test_sdk_super_helpers_do_not_add_business_interface_obligations(self):
        base, patch = self.root / 'sdk-super-interface-base', self.root / 'sdk-super-interface-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_sdk_super_interfaces_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_sdk_super_interfaces_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        source = (base / 'source.dart').read_text()
        self.assertIn('Invalid generated super bridge receiver', source)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(manifest['replaced_classes'], [])
        self.assertEqual(self.names(manifest, manifest['changed_functions']), ['BaseView.read'])
        for name in ['main', 'consume', 'update', 'Implemented.read', 'Mock.noSuchMethod']:
            self.assertNotIn(name, self.names(manifest, manifest['module_only_functions']))

    def test_sdk_super_index_bridge_preserves_distinct_read_write_types(self):
        base, patch = self.root / 'sdk-super-index-base', self.root / 'sdk-super-index-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_sdk_super_checks_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_sdk_super_checks_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        source = (base / 'source.dart').read_text()
        self.assertIn('<Object?, int, String?, String>', source)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(manifest['replaced_classes'], [])
        self.assertEqual(self.names(manifest, manifest['changed_functions']), ['Child.index'])

    def test_private_interfaces_preserve_aot_consumers_and_real_implementations(self):
        base, patch = self.root / 'private-base', self.root / 'private-patch'
        for action, side, args in [('baseline', 'baseline', [base]), ('patch', 'patch', [base, patch])]:
            result = self.command(action, ROOT / f'compiler/fixtures/aot_private_interfaces_{side}/app.dart', *args)
            self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(manifest['replaced_classes'], [])
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['Added'])
        self.assertEqual(self.names(manifest, manifest['installed_functions']), ['make'])
        self.assertEqual(manifest['module_only_functions'], [])
        self.assertIn('NoSuchMethodError.withInvocation', (base / 'source.dart').read_text())
        self.assertNotIn('Invocation.genericMethod', (base / 'source.dart').read_text())

    def test_patch_can_first_require_private_interface_forwarders(self):
        base, patch = self.root / 'private-added-base', self.root / 'private-added-patch'
        for action, side, args in [('baseline', 'baseline', [base]), ('patch', 'patch', [base, patch])]:
            result = self.command(action, ROOT / f'compiler/fixtures/aot_private_interface_added_{side}/app.dart', *args)
            self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        user_classes = [s for s in manifest['added_classes'] if not manifest['entities'][s].get('generated')]
        self.assertEqual(self.names(manifest, user_classes), ['Added'])
        self.assertEqual(manifest['replaced_classes'], [])
        self.assertEqual(self.names(manifest, manifest['installed_functions']), ['make'])
        self.assertEqual(manifest['module_only_functions'], [])
        self.assertEqual(len(manifest['added_classes']), 7)

    def test_unused_private_interface_infrastructure_can_retire(self):
        base, patch = self.root / 'private-removed-base', self.root / 'private-removed-patch'
        for action, side, args in [('baseline', 'baseline', [base]), ('patch', 'patch', [base, patch])]:
            result = self.command(action, ROOT / f'compiler/fixtures/aot_private_interface_removed_{side}/app.dart', *args)
            self.assertEqual(result.returncode, 0, result.stderr)
        original = json.loads((base / 'manifest.json').read_text())
        manifest = json.loads((patch / 'manifest.json').read_text())
        retired = manifest['retired_infrastructure_classes']
        self.assertEqual(len(retired), 6)
        self.assertTrue(all(original['entities'][s]['generated'] == 'private-interface-trap' for s in retired))
        self.assertEqual(self.names(manifest, manifest['replaced_classes']), ['Added'])
        self.assertNotIn('consume', self.names(manifest, manifest['module_only_functions']))

    def test_super_fields_keep_parent_storage_and_aot_consumers(self):
        base, patch = self.root / 'super-fields-base', self.root / 'super-fields-patch'
        for action, fixture, args in [
            ('baseline', 'baseline', [base]), ('patch', 'patch', [base, patch])]:
            result = self.command(action, ROOT / f'compiler/fixtures/aot_super_fields_{fixture}/app.dart', *args)
            self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(manifest['replaced_classes'], [])
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['Added'])
        for name in ['main', 'invoke', 'observe', 'churn', 'mockRead', 'Mock.noSuchMethod']:
            self.assertNotIn(name, self.names(manifest, manifest['changed_functions']))
            self.assertNotIn(name, self.names(manifest, manifest['module_only_functions']))
        for name in ['Child.update', 'Child.firstSuper', 'PrivateChild.update', 'make']:
            self.assertIn(name, self.names(manifest, manifest['installed_functions']))

    def test_super_field_illegal_writes_and_cross_library_privacy_rejected(self):
        for name, text in {
            'final': 'class B { final int x = 1; } class C extends B { void f() { super.x = 2; } } void main() {}',
            'type': 'class B<T> { T? x; } class C extends B<int> { void f() { super.x = "bad"; } } void main() {}',
            'private': "import 'private_base.dart'; class C extends B { int f() => super._x; } void main() {}",
        }.items():
            self.source('private_base.dart', 'class B { int _x = 1; }')
            result = self.command('baseline', self.source(name + '.dart', text), self.root / (name + '-output'))
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertIn('Static source errors', result.stderr)

    def test_static_methods_share_baseline_storage_and_relink_changed_classes(self):
        base, patch = self.root / 'static-base', self.root / 'static-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_static_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_static_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['replaced_classes']), ['Changing', 'Config', 'Settings'])
        module_only = self.names(manifest, manifest['module_only_functions'])
        self.assertIn('Changing.read', module_only)
        self.assertIn('fromDefault', module_only)
        installed = self.names(manifest, manifest['installed_functions'])
        self.assertNotIn('Changing.read', installed)
        self.assertIn('Counter.add', installed)
        self.assertEqual(len([name for name in installed if name == 'Counter.current']), 2)
        for name in ['stableRead', 'stableToken', 'caught', 'invoke', 'churn']:
            self.assertNotIn(name, self.names(manifest, manifest['changed_functions']))
        self.assertNotIn('Counter', self.names(manifest, manifest['replaced_classes']))

    def test_static_context_does_not_capture_instance_type_or_inherit_statics(self):
        cases = [
            'class C<T> { static T echo(T value) => value; }',
            'class A { static int read() => 1; } class B extends A { int read() => super.read(); }',
            'class A { static int count = 1; } class B extends A { int read() => B.count; }',
        ]
        for index, declaration in enumerate(cases):
            source = self.source('invalid-static-' + str(index) + '.dart', declaration + ' void main() {}')
            result = self.command('baseline', source, self.root / ('invalid-static-' + str(index)))
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertIn('Static source errors', result.stderr)

    def test_super_parameters_preserve_defaults_and_dependency_relinking(self):
        base, patch = self.root / 'super-base', self.root / 'super-patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_super_parameters_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_super_parameters_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['replaced_classes']), ['Defaults', 'ForwardDefault'])
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['Added'])
        self.assertNotIn('invoke', self.names(manifest, manifest['changed_functions']))
        self.assertIn('Base.read', self.names(manifest, manifest['changed_functions']))

    def test_invalid_super_parameters_fail_before_emission(self):
        cases = [
            'class A { A({int x = 1}); } class B extends A { B({super.missing}); }',
            'class A { A(int x); } class B extends A { B(String super.x); }',
            'class A { A(int x); } class B extends A { B(super.x) : super(1); }',
        ]
        for index, declaration in enumerate(cases):
            output = self.root / ('invalid-super-' + str(index))
            source = self.source('invalid-super-' + str(index) + '.dart', declaration + ' void main() {}')
            result = self.command('baseline', source, output)
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertIn('Static source errors', result.stderr)
            self.assertFalse((output / 'app.dart').exists())

    def test_new_super_call_uses_existing_bridge(self):
        base = self.root / 'baseline'
        candidate = self.root / 'candidate'
        shutil.copytree(ROOT / 'compiler/fixtures/aot_classes_baseline', candidate)
        child = candidate / 'child.dart'
        child.write_text(child.read_text().replace('super.compute(delta) + 10', 'delta + 10'))
        result = self.command('baseline', candidate / 'app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_classes_baseline/app.dart', base, self.root / 'patch')
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.root / 'patch/manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['changed_functions']), ['Child.compute'])

    def test_new_subclasses_link_to_baseline_without_recompiling_callers(self):
        base, patch = self.root / 'baseline', self.root / 'patch'
        result = self.command('baseline', ROOT / 'compiler/fixtures/aot_new_classes_baseline/app.dart', base)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command('patch', ROOT / 'compiler/fixtures/aot_new_classes_patch/app.dart', base, patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((patch / 'manifest.json').read_text())
        self.assertEqual(self.names(manifest, manifest['added_classes']), ['Leaf', 'New', 'Payload'])
        self.assertEqual(self.names(manifest, manifest['changed_functions']), ['make'])
        self.assertEqual(self.names(manifest, manifest['added_functions']), ['Leaf.compute', 'New.compute', 'New.label', 'Payload.amount'])
        base_symbol = self.symbol(manifest, 'Base', 'app:base.dart')
        new_symbol = self.symbol(manifest, 'New', 'app:new.dart')
        source = (patch / 'module.dart').read_text()
        self.assertIn('extends simurghBaseline.' + base_symbol, source)
        self.assertIn('extends ' + new_symbol, source)
        interface = (base / 'dynamic_interface.yaml').read_text()
        self.assertIn('extendable:', interface)
        self.assertIn('can-be-overridden:', interface)
        self.assertIn(base_symbol, interface)

    def test_removed_class_and_extension_of_closed_baseline_are_rejected(self):
        source = self.source('app.dart', 'final class Closed {} void main() {}')
        base = self.root / 'baseline'
        result = self.command('baseline', source, base)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, candidate, diagnostic in [
            ('removed', 'void main() {}', 'Deleted classes'),
            ('extended', 'final class Closed {} final class Added extends Closed {} void main() {}', 'closed baseline class'),
        ]:
            with self.subTest(name=name):
                path = self.source(name + '.dart', candidate)
                output = self.root / (name + '-patch')
                result = self.command('patch', path, base, output)
                self.assertEqual(result.returncode, 2)
                self.assertIn(diagnostic, result.stderr)
                self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
