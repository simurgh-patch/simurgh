#!/usr/bin/env python3
"""Check real Flutter Kernel/bytecode compilation, without claiming engine execution."""
import argparse
import json
from pathlib import Path
import subprocess
from aot_lab import ROOT, ENGINE, SDK, DART_SOURCE, compiler_sha, sha, source_identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-dir', type=Path, required=True)
    parser.add_argument('--fixture', choices=['ui', 'foundation', 'extensions', 'extension-types', 'ffi'], default='ui')
    parser.add_argument('--output', type=Path, help='Fresh directory for compiler verification evidence')
    args = parser.parse_args()
    folder = args.run_dir.resolve()
    build = json.loads((folder / 'build.json').read_text())
    if build['state'] != 'compiled-not-executed' or build['target'] != 'flutter' or not build['compile_only']:
        raise ValueError('Expected an explicitly compile-only Flutter build')
    if build['compiler_sha256'] != compiler_sha() or build['identity'] != source_identity():
        raise ValueError('Compiler/source identity changed since compilation')
    if [s['name'] for s in build['steps']] != [
            'generate-baseline', 'generate-patch', 'kernel-no-aot', 'kernel-aot', 'snapshot', 'bytecode'] or \
            any(s['exit_code'] for s in build['steps']):
        raise ValueError('Flutter compilation did not complete')
    for name, record in build['artifacts'].items():
        if sha(folder / name) != record['sha256']:
            raise ValueError(f'Changed build artifact: {name}')
    if build.get('target_os') != 'macos':
        raise ValueError('Expected the explicit macOS host target')
    platform = Path(build['platform']['path'])
    if sha(platform) != build['platform']['sha256']:
        raise ValueError('Changed Flutter platform Kernel')
    destination = args.output.resolve() if args.output else folder / 'compiler-checks'
    destination.mkdir(exist_ok=False)
    report = {'kind': 'flutter-compiler-checks', 'fixture': args.fixture,
              'build_sha256': sha(folder / 'build.json'), 'verifier_sha256': sha(__file__), 'checks': [], 'engine_executed': False,
              'm1_passed': False, 'production_patch': False}

    def execute(name, command):
        command = list(map(str, command))
        process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        (destination / f'{name}.log').write_text(process.stdout + process.stderr)
        report['checks'].append({'name': name, 'command': command, 'exit_code': process.returncode})
        (destination / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        if process.returncode:
            raise RuntimeError(f'{name} failed')
        return process.stdout

    if args.fixture in {'foundation', 'extensions'}:
        framework = ROOT / '.engine-workspace/framework'
        revision = json.loads((ROOT / 'toolchain.lock.json').read_text())['framework_revision']
        actual = subprocess.check_output(['git', '-C', str(framework), 'rev-parse', 'HEAD'], text=True).strip()
        if actual != revision:
            raise ValueError('Foundation fixture requires the pinned framework revision')
        execute('framework-clean', ['git', '-C', framework, 'diff', '--exit-code', 'HEAD', '--',
                                   'packages/flutter/lib', 'packages/flutter/pubspec.yaml'])
        report['framework_revision'] = revision
    packages = ROOT / 'compiler/.dart_tool/package_config.json'
    dart = SDK / 'bin/dart'
    kernel_command = [dart, '--packages=' + str(packages), DART_SOURCE / 'pkg/vm/bin/gen_kernel.dart',
                      '--aot', '--target=flutter', '--target-os=macos', '--platform', platform, '--packages', packages,
                      '-Ddart.vm.product=true', '-Ddart.vm.profile=false']
    inspector = ROOT / 'compiler/bin/inspect_kernel_api.dart'
    baseline_graph = folder / 'baseline/source_graph.json'
    baseline_manifest = json.loads((folder / 'baseline/manifest.json').read_text())
    entry_library = baseline_manifest['emitted_libraries']['app:entry']
    baseline_api = json.loads(execute('generated-api', [dart, inspector,
                              folder / 'baseline/aot.dill', folder / 'baseline' / entry_library, baseline_graph]))
    patch = json.loads((folder / 'patch/manifest.json').read_text())
    installed = sorted(patch['entities'][s]['name'] for s in patch['installed_functions'])
    expected_installed = {'ffi': ['compute'], 'extension-types': ['LayoutInfo.project'], 'foundation': ['changed'], 'extensions': ['Count.getter measured'],
                          'ui': ['diskValue', 'getter platformMarker', 'origin', 'shade', 'worker']}[args.fixture]
    if installed != expected_installed or patch['replaced_classes'] or patch['replaced_globals']:
        raise ValueError('Flutter fixture should retain main/blender and SDK classes')
    report['source_api'] = {}
    for side in ['baseline', 'patch']:
        graph_path = folder / side / 'source_graph.json'
        graph = json.loads(graph_path.read_text())
        if graph['conditional_target'] != 'pinned-flutter-aot' or len(graph['sdk_source_hashes']) != 19:
            raise ValueError('Missing Flutter target and SDK source identity')
        for name, digest in graph['sdk_source_hashes'].items():
            if sha(ENGINE / 'flutter/lib/ui' / name.removeprefix('dart:ui/')) != digest:
                raise ValueError(f'Changed pinned UI source: {name}')
        reference = destination / f'source-{side}'
        reference.mkdir()
        for uri, record in {**graph['libraries'], **graph.get('conditional_sources', {})}.items():
            if uri.startswith('package:'):
                name, relative = uri.removeprefix('package:').split('/', 1)
                if name not in graph['packages']:
                    raise ValueError('Package missing from source archive')
                path = reference / 'packages' / name / 'lib' / relative
            elif uri.startswith('app:'):
                path = reference / ('app.dart' if uri == 'app:entry' else uri.removeprefix('app:'))
            else:
                raise ValueError(f'Unexpected source URI: {uri}')
            if not path.resolve().is_relative_to(reference.resolve()):
                raise ValueError(f'Unexpected source URI: {uri}')
            if args.fixture in {'foundation', 'extensions'} and uri.startswith('package:flutter/'):
                original = framework / 'packages/flutter/lib' / uri.removeprefix('package:flutter/')
                if sha(original) != record['source_sha256']:
                    raise ValueError(f'Foundation source differs from the pinned checkout: {uri}')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(record['source'])
        kernel = reference / 'source.dill'
        config = reference / 'package_config.json'
        config.write_text(json.dumps({'configVersion': 2, 'packages': [
            {'name': name, 'rootUri': (reference / 'packages' / name).as_uri() + '/',
             'packageUri': 'lib/', 'languageVersion': package['language_version']}
            for name, package in graph['packages'].items()
        ]}, indent=2) + '\n')
        if graph['entry_package_uri'] is not None:
            raise ValueError('These fixed fixtures require a file entry point')
        command = kernel_command.copy()
        command[command.index('--packages') + 1] = config
        execute(f'source-{side}-kernel', [*command, '--output', kernel, reference / 'app.dart'])
        api = json.loads(execute(f'source-{side}-api', [dart, inspector, kernel, reference / 'app.dart', graph_path]))
        if not api['sdk_ui_present'] or not baseline_api['sdk_ui_present'] or \
                api['returns'] != baseline_api['returns']:
            raise ValueError('Generated Flutter SDK signatures differ from original Kernel')
        selected = [Path(uri.removeprefix('file://')).name for uri in api['imports']]
        if args.fixture == 'ui' and ('flutter.dart' not in selected or 'fallback.dart' in selected):
            raise ValueError('Original Flutter compiler selected a different conditional branch')
        if args.fixture in {'foundation', 'extensions'}:
            language_kernel = reference / 'languages.dill'
            language_command = command.copy()
            language_command[language_command.index('--aot')] = '--no-aot'
            execute(f'source-{side}-language-kernel', [*language_command,
                '--output', language_kernel, reference / 'app.dart'])
            versions = json.loads(execute(f'source-{side}-languages', [dart,
                ROOT / 'compiler/bin/inspect_kernel_languages.dart', language_kernel, reference]))
            for uri, version in graph['library_language_versions'].items():
                filename = ('app.dart' if uri == 'app:entry' else
                            'packages/' + uri.removeprefix('package:').replace('/', '/lib/', 1)
                            if uri.startswith('package:') else uri.removeprefix('app:'))
                if versions.get(filename) != version:
                    raise ValueError(f'Original Kernel language differs: {uri}')
            report.setdefault('source_languages', {})[side] = versions
        report['source_api'][side] = {'kernel_sha256': sha(kernel), 'api': api}
    graph = json.loads(baseline_graph.read_text())
    if args.fixture in {'foundation', 'extensions'}:
        versions = json.loads(execute('generated-languages', [dart,
            ROOT / 'compiler/bin/inspect_kernel_languages.dart', folder / 'baseline/no-aot.dill',
            folder / 'baseline']))
        for uri, filename in baseline_manifest['emitted_libraries'].items():
            if versions.get(filename) != graph['library_language_versions'][uri]:
                raise ValueError(f'Generated Kernel language differs: {uri}')
        report['generated_languages'] = versions
    condition_root = destination / 'conditions'
    condition_root.mkdir()
    source = condition_root / 'app.dart'
    environment = graph['conditional_environment']
    lines = [f"const condition_{i} = String.fromEnvironment({json.dumps(name)}, defaultValue: 'absent');"
             for i, name in enumerate(environment)]
    lines.append('void main() { print([' + ','.join(f'condition_{i}' for i in range(len(environment))) + ']); }')
    source.write_text('\n'.join(lines) + '\n')
    kernel = condition_root / 'conditions.dill'
    execute('condition-kernel', [*kernel_command, '--output', kernel, source])
    actual = json.loads(execute('condition-values', [dart, inspector, kernel, source, baseline_graph]))
    expected = {f'condition_{i}': value or 'absent' for i, value in enumerate(environment.values())}
    if actual['string_lists'] != [list(expected.values())]:
        raise ValueError(f'Flutter conditions disagree with original CFE: {actual["string_lists"]}')
    report.update(all_passed=True, condition_values=expected, sdk_returns=baseline_api['returns'])
    (destination / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'compiler_checks': len(report['checks']), 'report': str(destination / 'report.json'),
                      'engine_executed': False}))


if __name__ == '__main__':
    main()
