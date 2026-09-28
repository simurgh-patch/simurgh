#!/usr/bin/env python3
"""Compare fixed host FFI fixtures with independently compiled original AOT.

This is neither mobile acceptance nor permission to change a native ABI.
"""
import argparse
import json
from pathlib import Path
import subprocess

from aot_lab import ROOT, SDK, DYNAMIC, DART_SOURCE, compiler_sha, sha, source_identity


FIXTURES = {
    'native': (['compute'], ['native:14'], ['native:77']),
    'struct': (['Pair.score', 'work'], ['struct:7:3:4'], ['struct:54:5:4']),
    'callback': (['compute', 'make'], ['callback:12'], ['callback:85']),
    'callback_gc': (['listen', 'main', 'make'],
                    ['allocation:12720', 'local:12:-99', 'listener:7'],
                    ['allocation:12720', 'local:75:-99', 'listener:205']),
    'address': (['compute'], ['address:7'], ['address:17']),
    'pointer': (['work'], ['pointer:7'], ['pointer:70']),
    'lookup': (['compute', 'target'], ['lookup:11'], ['lookup:30']),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-dir', type=Path, required=True)
    parser.add_argument('--fixture', choices=FIXTURES, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    folder, out = args.run_dir.resolve(), args.output.resolve()
    build = json.loads((folder / 'build.json').read_text())
    identity, compiler = source_identity(), compiler_sha()
    if (build['state'] != 'executed-not-m1-accepted' or build['target'] != 'vm'
            or build['compile_only'] or build['identity'] != identity
            or build['compiler_sha256'] != compiler or build['target_os'] != 'macos'):
        raise ValueError('Current pinned host VM execution required')
    if [s['name'] for s in build['steps']] != [
            'generate-baseline', 'generate-patch', 'kernel-no-aot', 'kernel-aot',
            'snapshot', 'bytecode', 'baseline-run', 'patched-run'] or any(
                s['exit_code'] for s in build['steps']):
        raise ValueError('Incomplete build')
    for name, record in build['artifacts'].items():
        if sha(folder / name) != record['sha256']:
            raise ValueError(f'Changed artifact: {name}')
    for name, digest in build['runtime_provenance']['artifacts'].items():
        if sha(DYNAMIC / name) != digest:
            raise ValueError(f'Changed runtime: {name}')
    if any(build['runtime_provenance'].get(k) != v for k, v in identity.items()):
        raise ValueError('Runtime/source mismatch')
    platform = Path(build['platform']['path'])
    if sha(platform) != build['platform']['sha256']:
        raise ValueError('Changed platform')
    patch = json.loads((folder / 'patch/manifest.json').read_text())
    installed, expected_base, expected_patch = FIXTURES[args.fixture]
    if sorted(patch['entities'][s]['name'] for s in patch['installed_functions']) != installed:
        raise ValueError('Unexpected installed functions')
    if any(patch[k] for k in ['replaced_classes', 'replaced_globals', 'module_only_functions']):
        raise ValueError('Native fixture must retain its AOT layout')
    out.mkdir(parents=True, exist_ok=False)
    report = {'fixture': args.fixture, 'checks': [], 'identity': identity,
              'compiler_sha256': compiler, 'verifier_sha256': sha(__file__),
              'build_sha256': sha(folder / 'build.json'), 'installed_functions': installed,
              'runtime_provenance': build['runtime_provenance'],
              'm1_passed': False, 'device_accepted': False, 'production_patch': False}

    def save():
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(name, command, expected=None):
        command = list(map(str, command))
        process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
        (out / f'{name}.log').write_text(process.stdout + process.stderr)
        passed = process.returncode == 0 and (expected is None or process.stdout.splitlines() == expected)
        report['checks'].append({'name': name, 'command': command, 'exit_code': process.returncode,
                                 'stdout': process.stdout, 'passed': passed})
        save()
        if not passed:
            raise RuntimeError(f'{name} failed; inspect {out}')
        return process

    base = folder / 'baseline/app.aot'
    before = sha(base)
    packages = ROOT / 'compiler/.dart_tool/package_config.json'
    for side, expected in [('baseline', expected_base), ('patch', expected_patch)]:
        graph = json.loads((folder / side / 'source_graph.json').read_text())
        if set(graph['libraries']) != {'app:entry'} or graph.get('packages'):
            raise ValueError('Verifier covers the fixed single-library fixtures only')
        original = graph['libraries']['app:entry']
        reference = out / side
        reference.mkdir()
        source = reference / 'app.dart'
        source.write_text(original['source'])
        if sha(source) != original['source_sha256'] or sha(source) != sha(
                ROOT / f'compiler/fixtures/aot_ffi_{args.fixture}_{side}/app.dart'):
            raise ValueError('Source archive does not match the fixed fixture')
        kernel, aot = reference / 'source.dill', reference / 'source.aot'
        run(f'{side}-kernel', [SDK / 'bin/dart', '--packages=' + str(packages),
            DART_SOURCE / 'pkg/vm/bin/gen_kernel.dart', '--aot', '--target=vm',
            '--target-os=macos', '--platform', platform, '--packages', packages,
            '-Ddart.vm.product=true', '-Ddart.vm.profile=false', '--output', kernel, source])
        run(f'{side}-snapshot', [DYNAMIC / 'gen_snapshot', '--snapshot-kind=app-aot-elf',
                                 '--elf=' + str(aot), kernel])
        run(f'{side}-original', [DYNAMIC / 'dartaotruntime', aot], expected)
        run(f'{side}-mixed', [DYNAMIC / 'dartaotruntime', base] +
            ([folder / 'patch/patch.bytecode'] if side == 'patch' else []), expected)
        report.setdefault('original_artifacts', {})[side] = {
            'source_sha256': sha(source), 'kernel_sha256': sha(kernel), 'aot_sha256': sha(aot)}
    if args.fixture == 'callback_gc':
        gc = run('callback-forced-gc', [DYNAMIC / 'dartaotruntime',
            '--new_gen_semi_max_size=1', '--verbose_gc', base, folder / 'patch/patch.bytecode'], expected_patch)
        report['scavenges'] = (gc.stdout + gc.stderr).count('Scavenge(')
        if not report['scavenges']:
            raise ValueError('No collection observed across native callback closures')
    if sha(base) != before or source_identity() != identity or compiler_sha() != compiler:
        raise ValueError('Inputs changed during verification')
    report.update(all_passed=True, baseline_aot_unchanged=True)
    save()
    print(json.dumps({'checks': len(report['checks']), 'report': str(out / 'report.json')}))


if __name__ == '__main__':
    main()
