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
    platform = Path(build['platform']['path'])
    if sha(platform) != build['platform']['sha256']:
        raise ValueError('Changed Flutter platform Kernel')
    destination = args.output.resolve() if args.output else folder / 'compiler-checks'
    destination.mkdir(exist_ok=False)
    report = {'kind': 'flutter-compiler-checks', 'checks': [], 'engine_executed': False,
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

    packages = ROOT / 'compiler/.dart_tool/package_config.json'
    dart = SDK / 'bin/dart'
    kernel_command = [dart, '--packages=' + str(packages), DART_SOURCE / 'pkg/vm/bin/gen_kernel.dart',
                      '--aot', '--target=flutter', '--platform', platform, '--packages', packages,
                      '-Ddart.vm.product=true', '-Ddart.vm.profile=false']
    inspector = ROOT / 'compiler/bin/inspect_kernel_api.dart'
    baseline_graph = folder / 'baseline/source_graph.json'
    baseline_api = json.loads(execute('generated-api', [dart, inspector,
                              folder / 'baseline/aot.dill', folder / 'baseline/app.dart', baseline_graph]))
    patch = json.loads((folder / 'patch/manifest.json').read_text())
    installed = sorted(patch['entities'][s]['name'] for s in patch['installed_functions'])
    if installed != ['diskValue', 'origin', 'shade', 'worker'] or patch['replaced_classes'] or patch['replaced_globals']:
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
        for uri, record in {**graph['libraries'], **graph['conditional_sources']}.items():
            path = reference / ('app.dart' if uri == 'app:entry' else uri.removeprefix('app:'))
            if not uri.startswith('app:') or not path.resolve().is_relative_to(reference.resolve()):
                raise ValueError(f'Unexpected source URI: {uri}')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(record['source'])
        kernel = reference / 'source.dill'
        execute(f'source-{side}-kernel', [*kernel_command, '--output', kernel, reference / 'app.dart'])
        api = json.loads(execute(f'source-{side}-api', [dart, inspector, kernel, reference / 'app.dart', graph_path]))
        if not api['sdk_ui_present'] or not baseline_api['sdk_ui_present'] or \
                api['returns'] != baseline_api['returns']:
            raise ValueError('Generated Flutter SDK signatures differ from original Kernel')
        selected = [Path(uri.removeprefix('file://')).name for uri in api['imports']]
        if 'flutter.dart' not in selected or 'fallback.dart' in selected:
            raise ValueError('Original Flutter compiler selected a different conditional branch')
        report['source_api'][side] = {'kernel_sha256': sha(kernel), 'api': api}
    graph = json.loads(baseline_graph.read_text())
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
