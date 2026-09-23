#!/usr/bin/env python3
"""Build an experimental automatic AOT/bytecode function-replacement experiment.

Not a release/patch publisher. Does not implement Flutter/class-layout support,
network loading, production signatures, rollback or performance acceptance.
"""
import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from urllib.parse import urljoin

from runtime_sources import verify_runtime_sources, PATCHES

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / '.engine-workspace/engine/engine/src'
DART_SOURCE = ENGINE / 'flutter/third_party/dart'
SDK = ENGINE / 'out/host_release_arm64/dart-sdk'
DYNAMIC = ENGINE / 'out/host_release_arm64_dynamic'
NINJA = ROOT / '.engine-workspace/engine/third_party/ninja/ninja'
RUNTIME_MANIFEST = ROOT / 'output/m1-runtime-provenance.json'


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def compiler_sha():
    components = ''.join(f'{name}\0{sha(ROOT / "compiler" / name)}\n' for name in
                         ['bin/aot_patch.dart', 'lib/source_graph.dart', 'lib/class_lowering.dart', '../runtime/patches/manifest.json'])
    return hashlib.sha256(components.encode()).hexdigest()


def source_identity():
    lock = json.loads((ROOT / 'toolchain.lock.json').read_text())
    for folder, revision in [(ENGINE / 'flutter', lock['engine_revision']),
                             (DART_SOURCE, lock['dart_revision'])]:
        actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=folder, text=True).strip()
        if actual != revision:
            raise ValueError(f'Unpinned source checkout: {folder}')
        dirty = subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=folder, text=True)
        if dirty.strip() and folder != DART_SOURCE:
            raise ValueError(f'Upstream modifications need explicit provenance support: {folder}')
    return {'toolchain_sha256': sha(ROOT / 'toolchain.lock.json'),
            'engine_revision': lock['engine_revision'], 'dart_revision': lock['dart_revision'],
            **verify_runtime_sources(DART_SOURCE)}


def prepare_package_config():
    source = DART_SOURCE / '.dart_tool/package_config.json'
    config = json.loads(source.read_text())
    for package in config['packages']:
        package['rootUri'] = urljoin(source.as_uri(), package['rootUri'])
    config['packages'].append({'name': 'simurgh_compiler_lab',
                              'rootUri': (ROOT / 'compiler').as_uri() + '/',
                              'packageUri': 'lib/', 'languageVersion': '3.12'})
    output = ROOT / 'compiler/.dart_tool/package_config.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(config, indent=2) + '\n')
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, default=ROOT / 'compiler/fixtures/aot_baseline/app.dart')
    parser.add_argument('--candidate', type=Path, default=ROOT / 'compiler/fixtures/aot_patch/app.dart')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--build-runtime', action='store_true', help='Build dedicated dynamic-module AOT runtime; uses existing user-authorized disk override')
    args = parser.parse_args()
    identity = source_identity()
    packages = prepare_package_config()
    if args.output:
        output = args.output.resolve()
        output.mkdir(parents=True, exist_ok=False)
    else:
        output = Path(tempfile.mkdtemp(prefix=datetime.now(timezone.utc).strftime('m1-aot-%Y%m%dT%H%M%SZ-'), dir=ROOT / 'output'))
    report = {'kind': 'experimental-aot-function-replacement', 'state': 'building',
              'identity': identity, 'compiler_sha256': compiler_sha(),
              'runner_sha256': sha(__file__), 'steps': [], 'complete_runtime_implemented': False,
              'm1_passed': False, 'production_patch': False}
    env = os.environ.copy()
    env['PATH'] = str(ROOT / '.tools/depot_tools') + os.pathsep + env.get('PATH', '')
    env['DEPOT_TOOLS_UPDATE'] = '0'

    def save():
        (output / 'build.json').write_text(json.dumps(report, indent=2) + '\n')

    def run(name, command, cwd=ROOT):
        step = {'name': name, 'command': [str(x) for x in command], 'log': name + '.log'}
        report['steps'].append(step)
        save()
        with (output / step['log']).open('w') as log:
            step['exit_code'] = subprocess.run(step['command'], cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT).returncode
        save()
        print(f"{name}: {step['exit_code']}", flush=True)
        if step['exit_code']:
            raise RuntimeError(f"{name} failed; see {output / step['log']}")

    save()
    print(f'Output: {output}', flush=True)
    try:
        if args.build_runtime:
            # Keep the previous verified runtime usable as historical evidence.
            if RUNTIME_MANIFEST.exists():
                previous = json.loads(RUNTIME_MANIFEST.read_text())
                archive = ROOT / 'output/runtime-archive' / sha(RUNTIME_MANIFEST)
                archive.mkdir(parents=True, exist_ok=True)
                for name, expected in previous['artifacts'].items():
                    if not (archive / name).exists():
                        if sha(DYNAMIC / name) != expected:
                            raise ValueError(f'Previous runtime changed before archival: {name}')
                        shutil.copy2(DYNAMIC / name, archive / name)
                    if sha(archive / name) != expected:
                        raise ValueError(f'Archived runtime mismatch: {name}')
                shutil.copy2(RUNTIME_MANIFEST, archive / 'provenance.json')
            shutil.copytree(PATCHES, output / 'runtime-patches')
            run('gn', [sys.executable, 'flutter/tools/gn', '--runtime-mode', 'release', '--mac-cpu', 'arm64',
                       '--no-rbe', '--no-goma', '--no-prebuilt-dart-sdk', '--dart-dynamic-modules',
                       '--target-dir', DYNAMIC.name], cwd=ENGINE)
            run('ninja', [NINJA, '-j2', '-C', DYNAMIC, 'dartaotruntime', 'gen_snapshot'])
            if source_identity() != identity:
                raise ValueError('Source identity changed during runtime build')
            RUNTIME_MANIFEST.write_text(json.dumps({**identity, 'artifacts': {
                name: sha(DYNAMIC / name) for name in ['dartaotruntime', 'gen_snapshot', 'args.gn']
            }}, indent=2) + '\n')
        provenance = json.loads(RUNTIME_MANIFEST.read_text())
        if any(provenance.get(key) != value for key, value in identity.items()):
            raise ValueError('Runtime provenance differs from source lock; rebuild explicitly')
        for name, digest in provenance['artifacts'].items():
            if sha(DYNAMIC / name) != digest:
                raise ValueError(f'Runtime artifact changed: {name}')
        report['runtime_provenance'] = provenance
        base, patch = output / 'baseline', output / 'patch'
        tool = [SDK / 'bin/dart', ROOT / 'compiler/bin/aot_patch.dart']
        run('generate-baseline', [*tool, 'baseline', args.baseline.resolve(), base])
        run('generate-patch', [*tool, 'patch', args.candidate.resolve(), base, patch])
        runtime = SDK / 'bin/dart'
        platform = SDK / 'lib/_internal/vm_platform_strong.dill'
        for mode in ['no-aot', 'aot']:
            run('kernel-' + mode, [runtime, '--packages=' + str(packages), DART_SOURCE / 'pkg/vm/bin/gen_kernel.dart', '--' + mode,
                                  '--platform', platform, '--packages', packages, '--dynamic-interface',
                                  base / 'dynamic_interface.yaml', '-Ddart.vm.product=true', '-Ddart.vm.profile=false',
                                  '--output', base / (mode + '.dill'), base / 'launcher.dart'])
        run('snapshot', [DYNAMIC / 'gen_snapshot', '--snapshot-kind=app-aot-elf', '--elf=' + str(base / 'app.aot'), base / 'aot.dill'])
        before_hash = sha(base / 'app.aot')
        run('bytecode', [runtime, '--packages=' + str(packages), DART_SOURCE / 'pkg/dart2bytecode/bin/dart2bytecode.dart', '--platform', platform,
                         '--packages', packages, '--import-dill', base / 'no-aot.dill', '--validate', base / 'dynamic_interface.yaml',
                         '-Ddart.vm.product=true', '-Ddart.vm.profile=false', '--output', patch / 'patch.bytecode', patch / 'module.dart'])
        run('baseline-run', [DYNAMIC / 'dartaotruntime', base / 'app.aot'])
        run('patched-run', [DYNAMIC / 'dartaotruntime', base / 'app.aot', patch / 'patch.bytecode'])
        if sha(base / 'app.aot') != before_hash:
            raise ValueError('Baseline AOT binary was modified during patch execution')
        report['artifacts'] = {str(path.relative_to(output)): {'bytes': path.stat().st_size, 'sha256': sha(path)}
                               for path in [base / 'app.aot', patch / 'patch.bytecode', base / 'manifest.json', patch / 'manifest.json',
                                            base / 'source_graph.json', patch / 'source_graph.json', base / 'dynamic_interface.yaml', *sorted(base.glob('*.dart')), *sorted(patch.glob('*.dart'))]}
        report['baseline_stdout'] = (output / 'baseline-run.log').read_text()
        report['patched_stdout'] = (output / 'patched-run.log').read_text()
        # Exit 0 means compilation/execution succeeded, not that arbitrary user
        # program behavior is correct. Assertions belong to acceptance fixtures.
        report['state'] = 'executed-not-m1-accepted'
        print(report['baseline_stdout'], end='')
        print(report['patched_stdout'], end='')
        save()
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        report.update(state='failed', error=str(error))
        save()
        print(error, file=sys.stderr)
        return 2


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(2)
