#!/usr/bin/env python3
"""Pinned reference or patched mixed-runtime engine builds; default is read-only."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MINIMUM_BYTES = 200 * 1024**3
sys.path.insert(0, str(Path(__file__).resolve().parent))
from runtime_sources import verify_runtime_sources, PATCHES


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def recipes(profile='reference', targets=None):
    common = ['--runtime-mode', 'release', '--no-rbe', '--no-goma']
    result = [
        ('host_release_arm64', common + ['--mac-cpu', 'arm64', '--no-prebuilt-dart-sdk'],
         ['dart-sdk/bin/dart', 'gen/frontend_server_aot.dart.snapshot']),
        ('android_release_arm64', common + ['--android', '--android-cpu', 'arm64'],
         ['libflutter.so', 'flutter.jar']),
        ('ios_release', common + ['--ios'], ['Flutter.framework/Flutter']),
    ]

    if profile not in ('reference', 'mixed'):
        raise ValueError('Unknown engine build profile')
    selected = set(targets or ['host', 'android', 'ios'])
    if not selected <= {'host', 'android', 'ios'}:
        raise ValueError('Unknown engine build target')
    output = []
    for platform, (name, flags, required) in zip(['host', 'android', 'ios'], result):
        if platform not in selected:
            continue
        if profile == 'mixed':
            name += '_mixed'
            flags = [*flags, '--dart-dynamic-modules', '--target-dir', name]
            if '--no-prebuilt-dart-sdk' not in flags:
                flags.append('--no-prebuilt-dart-sdk')
            if platform == 'host':
                required = [*required, 'gen_snapshot']
        output.append((name, flags, required))
    return output


def capture(command, cwd, env):
    return subprocess.run(command, cwd=cwd, env=env, check=True, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.strip()


def preflight(workspace, lock, env, available=None, ignore_space_check=False, allowed_outputs=(), profile='reference', targets=None):
    errors = []
    runtime_sources = None
    parent = workspace
    while not parent.exists():
        parent = parent.parent
    free = shutil.disk_usage(parent).free if available is None else available
    budget = lock.get('engine_workspace_min_free_bytes')
    if type(budget) is not int or budget < MINIMUM_BYTES or (free < budget and not ignore_space_check):
        errors.append('Build requires at least the locked 200 GiB free-space budget')
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        errors.append('This recipe requires native Apple Silicon macOS')
    for tool in ('git', 'xcrun', 'xcodebuild'):
        if not shutil.which(tool, path=env['PATH']):
            errors.append(f'Missing tool: {tool}')
    revisions = ('framework_revision', 'engine_revision', 'dart_revision', 'depot_tools_revision')
    for key in revisions:
        if not re.fullmatch(r'[0-9a-f]{40}', str(lock.get(key, ''))):
            errors.append(f'Invalid lock revision: {key}')
    try:
        marker = json.loads((workspace / 'prepare-state.json').read_text())
        if marker.get('state') != 'sources-ready-not-built':
            errors.append('Source preparation did not complete')
        for key in revisions:
            if marker.get(key) != lock.get(key):
                errors.append(f'Preparation lock mismatch: {key}')
    except (OSError, ValueError, AttributeError):
        errors.append('Missing or invalid prepare-state.json; prepare sources first')
    src = workspace / 'engine/engine/src'
    checkouts = [
        (workspace / 'framework', 'framework_revision'),
        (workspace / 'engine', 'engine_revision'),
        (src / 'flutter/third_party/dart', 'dart_revision'),
        (ROOT / '.tools/depot_tools', 'depot_tools_revision'),
    ]
    for path, key in checkouts:
        try:
            # Prevent git from silently resolving an enclosing repository.
            top = Path(capture(['git', 'rev-parse', '--show-toplevel'], path, env)).resolve()
            if top != path.resolve() or path.is_symlink():
                raise ValueError('Not an independent checkout')
            if capture(['git', 'rev-parse', 'HEAD'], path, env) != lock.get(key):
                raise ValueError('Revision mismatch')
            if key == 'dart_revision' and profile == 'mixed':
                runtime_sources = verify_runtime_sources(path)
                if capture(['git', 'ls-files', '--others', '--exclude-standard'], path, env):
                    raise ValueError('Runtime checkout contains untracked source files')
            elif capture(['git', 'status', '--porcelain', '--untracked-files=normal'], path, env):
                raise ValueError('Checkout contains changes or untracked files')
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            errors.append(f'{key}: {error}')
    try:
        deps = (workspace / 'engine/DEPS').read_text()
        match = re.search(r"'dart_revision':\s*'([a-f0-9]{40})'", deps)
        if not match or match.group(1) != lock.get('dart_revision'):
            errors.append('Engine DEPS does not match locked Dart revision')
        if (workspace / 'engine/.gclient').read_bytes() != (workspace / 'engine/engine/scripts/standard.gclient').read_bytes():
            errors.append('gclient configuration differs from pinned template')
    except OSError:
        errors.append('Missing DEPS or gclient configuration')
    if not (src / 'flutter/tools/gn').is_file():
        errors.append('Missing engine GN entry point')
    for name, _, _ in recipes(profile, targets):
        if (src / 'out' / name).exists() and name not in allowed_outputs:
            errors.append(f'Output already exists: {name}; preserve it and use a fresh source workspace')
    ninja = workspace / 'engine/third_party/ninja/ninja'
    if not ninja.is_file() or not os.access(ninja, os.X_OK):
        errors.append('Missing executable Ninja from pinned engine DEPS')
    versions = {}
    if not errors:
        for label, command in [('xcode', ['xcodebuild', '-version']),
                               ('iphoneos_sdk', ['xcrun', '--sdk', 'iphoneos', '--show-sdk-version']),
                               ('clang', ['xcrun', 'clang', '--version']),
                               ('metal', ['xcrun', 'metal', '--version']),
                               ('ninja', [str(ninja), '--version'])]:
            try:
                versions[label] = capture(command, workspace, env)
            except (OSError, subprocess.CalledProcessError) as error:
                errors.append(f'{label}: {error}; {getattr(error, "stderr", "") or ""}'.strip())
    return {'errors': errors, 'available_bytes': free, 'host_versions': versions,
            'runtime_sources': runtime_sources}


def execute(workspace, report, destination, env, jobs):
    """Destination must be newly allocated by caller; failure always retains evidence."""
    src = workspace / 'engine/engine/src'
    manifest = {**report, 'state': 'building', 'steps': [], 'artifacts': [],
                'runtime_implemented': False, 'm0_passed': False}
    path = destination / 'build.json'

    def save():
        temporary = destination / 'build.json.tmp'
        temporary.write_text(json.dumps(manifest, indent=2) + '\n')
        temporary.replace(path)

    save()
    try:
        manifest['dependency_revisions'] = capture(
            [str(ROOT / '.tools/depot_tools/gclient'), 'revinfo', '--actual'],
            workspace / 'engine', env)
        for name, flags, required in recipes(report.get('profile', 'reference'), report.get('targets')):
            for command in ([sys.executable, 'flutter/tools/gn', *flags],
                            [str(workspace / 'engine/third_party/ninja/ninja'), f'-j{jobs}', '-C', f'out/{name}']):
                log = destination / f'{len(manifest["steps"]):02d}-{name}.log'
                step = {'command': command, 'cwd': str(src), 'log': log.name, 'returncode': None}
                manifest['steps'].append(step)
                save()
                with log.open('x') as stream:
                    result = subprocess.run(command, cwd=src, env=env, stdout=stream,
                                            stderr=subprocess.STDOUT, check=False)
                step['returncode'] = result.returncode
                save()
                if result.returncode:
                    raise RuntimeError(f'Command failed ({result.returncode}); see {log}')
            output = src / 'out' / name
            for relative in ['args.gn', *required]:
                artifact = output / relative
                if not artifact.resolve().is_relative_to(output.resolve()):
                    raise RuntimeError(f'Artifact escapes build output: {artifact}')
                if not artifact.is_file() or artifact.stat().st_size == 0:
                    raise RuntimeError(f'Missing or empty expected artifact: {artifact}')
                manifest['artifacts'].append({'path': str(artifact), 'size': artifact.stat().st_size,
                                              'sha256': sha256(artifact)})
            shutil.copyfile(output / 'args.gn', destination / f'{name}-args.gn')
        if capture([str(ROOT / '.tools/depot_tools/gclient'), 'revinfo', '--actual'],
                   workspace / 'engine', env) != manifest['dependency_revisions']:
            raise RuntimeError('Dependency revisions changed during build')
        for checkout, revision in [(workspace / 'framework', 'framework_revision'),
                                   (workspace / 'engine', 'engine_revision'),
                                   (src / 'flutter/third_party/dart', 'dart_revision')]:
            if capture(['git', 'rev-parse', 'HEAD'], checkout, env) != report['lock'][revision]:
                raise RuntimeError(f'Source changed during build: {revision}')
            if revision == 'dart_revision' and report.get('profile') == 'mixed':
                if (verify_runtime_sources(checkout) != report.get('runtime_sources') or
                        capture(['git', 'ls-files', '--others', '--exclude-standard'], checkout, env)):
                    raise RuntimeError('Runtime source patch set changed during build')
            elif capture(['git', 'status', '--porcelain', '--untracked-files=normal'], checkout, env):
                raise RuntimeError(f'Source changed during build: {revision}')
        # Compilation is not installation, reproducibility or device acceptance.
        manifest['state'] = 'compiled-not-device-validated'
        save()
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError, KeyboardInterrupt) as error:
        manifest.update(state='failed', error=str(error) or 'Interrupted')
        save()
        return 2


def validate_resume(path, workspace, lock, profile='reference', targets=None):
    """Only a failed run from this project's evidence store may authorize reuse."""
    path = path.expanduser().resolve()
    if path.name != 'build.json' or not path.is_relative_to((ROOT / 'output/engine-builds').resolve()):
        raise ValueError('Resume manifest must be a build.json in this project engine-builds directory')
    previous = json.loads(path.read_text())
    expected = [{'output': name, 'gn_flags': flags, 'required_artifacts': required}
                for name, flags, required in recipes(profile, targets)]
    if (previous.get('state') != 'failed' or previous.get('workspace') != str(workspace)
            or previous.get('lock') != lock or previous.get('recipes') != expected):
        raise ValueError('Resume requires a failed run with the same workspace, lock and recipes')
    if previous.get('profile', 'reference') != profile:
        raise ValueError('Resume build profile differs')
    if profile == 'mixed' and previous.get('runtime_sources') != verify_runtime_sources(workspace / 'engine/engine/src/flutter/third_party/dart'):
        raise ValueError('Resume runtime patch identity differs')
    allowed = []
    for name, flags, _ in recipes(profile, targets):
        if any(step.get('cwd') == str(workspace / 'engine/engine/src')
               and isinstance(step.get('command'), list)
               and step['command'][1:] == ['flutter/tools/gn', *flags]
               for step in previous.get('steps', [])):
            allowed.append(name)
    return allowed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-root', type=Path, required=True)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--profile', choices=['reference', 'mixed'], default='reference')
    parser.add_argument('--targets', nargs='+', choices=['host', 'android', 'ios'], default=['host', 'android', 'ios'])
    parser.add_argument('--resume-build', type=Path, help='Reuse outputs authorized by a matching failed build manifest')
    parser.add_argument('--jobs', type=int, choices=range(1, 3), default=2)
    parser.add_argument('--ignore-space-check', action='store_true', help='Explicitly attempt build despite insufficient free space')
    args = parser.parse_args()
    workspace = args.build_root.expanduser().resolve()
    lock = json.loads((ROOT / 'toolchain.lock.json').read_text())
    env = {**os.environ, 'DEPOT_TOOLS_UPDATE': '0',
           'PATH': str(ROOT / '.tools/depot_tools') + os.pathsep + os.environ.get('PATH', '')}
    for variable in ('CPATH', 'LIBRARY_PATH', 'SDKROOT'):
        env.pop(variable, None)
    resume_errors = []
    allowed_outputs = []
    if args.resume_build:
        try:
            allowed_outputs = validate_resume(args.resume_build, workspace, lock, args.profile, args.targets)
        except (OSError, ValueError, TypeError, AttributeError) as error:
            resume_errors.append(str(error))
    report = {**preflight(workspace, lock, env, ignore_space_check=args.ignore_space_check,
                         allowed_outputs=allowed_outputs, profile=args.profile, targets=args.targets), 'workspace': str(workspace),
              'profile': args.profile, 'targets': args.targets,
              'lock': lock, 'lock_sha256': sha256(ROOT / 'toolchain.lock.json'),
              'script_sha256': sha256(Path(__file__)), 'python': sys.version,
              'jobs': args.jobs, 'executed': False, 'space_check_overridden': args.ignore_space_check,
              'recipes': [{'output': name, 'gn_flags': flags, 'required_artifacts': required}
                          for name, flags, required in recipes(args.profile, args.targets)]}
    report['errors'].extend(resume_errors)
    if args.resume_build and not resume_errors:
        report['resumed_from'] = str(args.resume_build.expanduser().resolve())
        report['resume_manifest_sha256'] = sha256(args.resume_build.expanduser().resolve())
    if report['errors'] or not args.execute:
        print(json.dumps(report, indent=2))
        return 2 if report['errors'] else 0
    output = ROOT / 'output/engine-builds'
    output.mkdir(parents=True, exist_ok=True)
    destination = Path(tempfile.mkdtemp(prefix=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ-'), dir=output))
    shutil.copyfile(Path(__file__), destination / 'build_engine.py')
    shutil.copyfile(ROOT / 'toolchain.lock.json', destination / 'toolchain.lock.json')
    if args.profile == 'mixed':
        shutil.copytree(PATCHES, destination / 'runtime-patches')
        shutil.copyfile(ROOT / 'scripts/runtime_sources.py', destination / 'runtime_sources.py')
        report['runtime_sources_script_sha256'] = sha256(ROOT / 'scripts/runtime_sources.py')
    report['executed'] = True
    code = execute(workspace, report, destination, env, args.jobs)
    print(json.dumps({'exit_code': code, 'manifest': str(destination / 'build.json')}))
    return code


if __name__ == '__main__':
    sys.exit(main())
