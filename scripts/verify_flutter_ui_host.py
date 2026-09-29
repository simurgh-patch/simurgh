#!/usr/bin/env python3
"""Cold-process checks for UI/foundation fixtures in a matching host AOT engine.

Not a mobile runner, Widget acceptance suite, update client or production patch.
"""
import argparse
import json
from pathlib import Path
import subprocess

from aot_lab import ROOT, ENGINE, DYNAMIC, NINJA, compiler_sha, sha, source_identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-dir', type=Path, required=True)
    parser.add_argument('--engine-build', type=Path, required=True)
    parser.add_argument('--compiler-checks', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='Fresh verification directory')
    args = parser.parse_args()
    folder, checks, out = args.run_dir.resolve(), args.compiler_checks.resolve(), args.output.resolve()
    build = json.loads(args.engine_build.read_text())
    expected_command = [str(NINJA), '-j2', '-C', str(DYNAMIC), 'libflutter_engine.dylib']
    if build['state'] != 'compiled-not-executed' or build['exit_code'] != 0 or \
            not build['runtime_artifacts_unchanged'] or not build['identity_unchanged'] or \
            build['identity'] != source_identity() or build['command'] != expected_command:
        raise ValueError('Matching pinned host engine build required')
    if sha(DYNAMIC / 'libflutter_engine.dylib') != build['engine_sha256']:
        raise ValueError('Engine changed after compilation')
    for name, digest in build['runtime_provenance']['artifacts'].items():
        if sha(DYNAMIC / name) != digest:
            raise ValueError(f'Runtime tool changed: {name}')
    ui = json.loads((folder / 'build.json').read_text())
    if ui['compiler_sha256'] != compiler_sha() or ui['identity'] != build['identity'] or \
            ui['target'] != 'flutter' or ui['state'] != 'compiled-not-executed':
        raise ValueError('Compiler and engine identities differ')
    for name, record in ui['artifacts'].items():
        if sha(folder / name) != record['sha256']:
            raise ValueError(f'Changed compiler artifact: {name}')
    compiler_checks = json.loads((checks / 'report.json').read_text())
    if not compiler_checks['all_passed'] or compiler_checks['engine_executed'] or \
            compiler_checks['build_sha256'] != sha(folder / 'build.json'):
        raise ValueError('Successful independent compiler checks required')
    for side in ['baseline', 'patch']:
        if sha(checks / f'source-{side}/source.dill') != compiler_checks['source_api'][side]['kernel_sha256']:
            raise ValueError(f'Changed original-source Kernel: {side}')
    out.mkdir(parents=True, exist_ok=False)
    source = ROOT / 'runtime/probes/flutter_ui_fixture_runner.cc'
    report = {'kind': 'experimental-host-flutter-cold-start', 'fixture': compiler_checks['fixture'], 'checks': [],
              'engine_executed': False, 'device_accepted': False, 'm1_passed': False,
              'production_patch': False, 'engine_sha256': build['engine_sha256'],
              'identity': build['identity'], 'compiler_sha256': compiler_sha(),
              'probe_source_sha256': sha(source), 'verifier_sha256': sha(__file__),
              'compiler_checks_sha256': sha(checks / 'report.json')}

    if compiler_checks['fixture'] == 'widget':
        report.update(fixture_scope='widget-construction-only', widget_rendered=False)

    def save():
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(name, command):
        command = list(map(str, command))
        process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=40)
        (out / f'{name}.log').write_text(process.stdout + process.stderr)
        report['checks'].append({'name': name, 'command': command, 'exit_code': process.returncode,
                                 'stdout': process.stdout, 'stderr': process.stderr})
        save()
        if process.returncode:
            raise RuntimeError(f'{name} failed')
        return process.stdout

    probe, assets = out / 'fixture_runner', out / 'assets'
    assets.mkdir()
    icu = ENGINE / 'out/host_release_arm64/icudtl.dat'
    report['icu_sha256'] = sha(icu)
    # The macOS embedder dylib has a framework install name. Preserve the engine
    # bytes and provide that layout under this fresh test directory via symlink.
    framework = out / 'FlutterEmbedder.framework/Versions/A/FlutterEmbedder'
    framework.parent.mkdir(parents=True)
    framework.symlink_to(DYNAMIC / 'libflutter_engine.dylib')
    run('embedder-link', ['xcrun', 'clang++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
                         '-I', ENGINE / 'flutter/shell/platform/embedder', source,
                         '-L', DYNAMIC, '-lflutter_engine', '-Wl,-rpath,' + str(out), '-o', probe])
    report['probe_sha256'] = sha(probe)
    for side in ['baseline', 'patch']:
        run(f'source-{side}-snapshot', [DYNAMIC / 'gen_snapshot', '--snapshot-kind=app-aot-elf',
                                       '--elf=' + str(out / f'source-{side}.aot'),
                                       checks / f'source-{side}/source.dill'])
    base = folder / 'baseline/app.aot'
    before = sha(base)
    expected_base = ['io:base', 'platform-value:5', 'timeline:4', 'isolate:3', 'platform:flutter', 'color:4279383126', 'point:1.0:2.0', 'blend:4279383126']
    expected_patch = ['io:patch:5', 'platform-value:50', 'timeline:13', 'isolate:12', 'platform:flutter', 'color:4284826401', 'point:10.0:20.0', 'blend:4284826401']
    if compiler_checks['fixture'] == 'foundation':
        expected_base = ['notifier:4', "diagnostic:Instance of 'IntProperty'", 'blend:true']
        expected_patch = ['notifier:4', "diagnostic:Instance of 'IntProperty'", 'blend:false']
    elif compiler_checks['fixture'] == 'extensions':
        expected_base = ['clusters:3', 'unicode:2', 'blend:true']
        expected_patch = ['clusters:12', 'unicode:2', 'blend:false']
    elif compiler_checks['fixture'] == 'extension-types':
        expected_base = ['layout:7.0:20.0', 'callback:7.0:20.0', 'representation:true:2.0:13.0']
        expected_patch = ['layout:25.0:137.0', 'callback:25.0:137.0', 'representation:true:2.0:13.0']
    elif compiler_checks['fixture'] == 'widget':
        expected_base = ['SizedBox.shrink']
        expected_patch = ['SizedBox.expand']
    elif compiler_checks['fixture'] == 'scopes':
        expected_base = ['render:4.0:5.0', 'shadow:5.0:6.0', 'async:8.0:9.0']
        expected_patch = ['render:13.0:24.0', 'shadow:50.0:60.0', 'async:17.0:28.0']
    elif compiler_checks['fixture'] == 'constraints':
        expected_base = ['point:3.0:5.0', 'codec:MethodCall:paint']
        expected_patch = ['point:12.0:23.0', 'codec:MethodCall:paint']
    elif compiler_checks['fixture'] == 'ffi':
        expected_base = ['ffi:5.0:8.0', 'callback:5.0:8.0']
        expected_patch = ['ffi:23.0:8.0', 'callback:23.0:8.0']
    elif compiler_checks['fixture'] != 'ui':
        raise ValueError('Unknown fixture')
    for name, aot, patch, expected in [
            ('source-baseline', out / 'source-baseline.aot', None, expected_base),
            ('source-patch', out / 'source-patch.aot', None, expected_patch),
            ('mixed-baseline', base, None, expected_base),
            ('mixed-patch', base, folder / 'patch/patch.bytecode', expected_patch)]:
        stdout = run(name, [probe, aot, assets, icu, expected[-1]] + ([patch] if patch else []))
        if stdout.splitlines() != expected:
            raise ValueError(f'{name} output differs from source AOT')
    if sha(base) != before or sha(DYNAMIC / 'libflutter_engine.dylib') != build['engine_sha256']:
        raise ValueError('Baseline or engine bytes changed')
    report.update(engine_executed=True, all_passed=True, baseline_aot_unchanged=True,
                  baseline_aot_sha256=before)
    save()
    print(json.dumps({'engine_executed': True, 'checks': len(report['checks']), 'report': str(out / 'report.json')}))


if __name__ == '__main__':
    main()
