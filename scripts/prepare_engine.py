#!/usr/bin/env python3
"""Create pinned source checkouts only after the M0 storage/tool gates pass.

Does not build, modify the user's SDK, or claim a custom runtime exists.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
MINIMUM_BYTES = 200 * 1024**3


def check_workspace(workspace: Path, lock: dict, available: int, ignore_space_check: bool = False) -> list[str]:
    errors = []
    required = lock.get('engine_workspace_min_free_bytes')
    if not isinstance(required, int) or required < MINIMUM_BYTES:
        errors.append('Lock must retain the 200 GiB minimum workspace budget')
    elif available < required and not ignore_space_check:
        errors.append(f'Insufficient space: {available} bytes available, {required} required')
    for key in ('framework_revision', 'engine_revision', 'dart_revision'):
        if not re.fullmatch(r'[a-f0-9]{40}', str(lock.get(key, ''))):
            errors.append(f'Invalid locked revision: {key}')
    if workspace.exists() and (not workspace.is_dir() or any(workspace.iterdir())):
        errors.append('Destination must be absent or an empty directory; nothing will be overwritten')
    return errors


def run(args: list[str], cwd: Path) -> str:
    result = subprocess.run(args, cwd=cwd, check=True, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.stdout.strip()


def checkout(path: Path, revision: str, repository: str) -> None:
    path.mkdir()
    run(['git', 'init', '-b', 'codex/runtime-baseline'], path)
    run(['git', 'remote', 'add', 'upstream', repository], path)
    run(['git', 'fetch', '--depth=1', 'upstream', revision], path)
    run(['git', 'checkout', '-B', 'codex/runtime-baseline', 'FETCH_HEAD'], path)
    if run(['git', 'rev-parse', 'HEAD'], path) != revision:
        raise RuntimeError('Source revision mismatch')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-root', type=Path, required=True)
    parser.add_argument('--execute', action='store_true', help='Fetch sources and gclient dependencies after gates pass')
    parser.add_argument('--ignore-space-check', action='store_true', help='Explicitly attempt preparation despite insufficient free space')
    args = parser.parse_args()
    lock = json.loads((ROOT / 'toolchain.lock.json').read_text())
    depot = ROOT / '.tools/depot_tools'
    os.environ['PATH'] = str(depot) + os.pathsep + os.environ.get('PATH', '')
    os.environ['DEPOT_TOOLS_UPDATE'] = '0'
    workspace = args.build_root.expanduser().resolve()
    parent = workspace
    while not parent.exists():
        parent = parent.parent
    available = shutil.disk_usage(parent).free
    errors = check_workspace(workspace, lock, available, args.ignore_space_check)
    for tool in ('git', 'gclient'):
        if not shutil.which(tool):
            errors.append(f'Missing prerequisite: {tool}')
    report = {'workspace': str(workspace), 'available_bytes': available,
              'errors': errors, 'executed': False, 'space_check_overridden': args.ignore_space_check,
              'framework_revision': lock['framework_revision'],
              'engine_revision': lock['engine_revision'],
              'dart_revision': lock['dart_revision']}
    if depot.is_dir():
        try:
            if run(['git', 'rev-parse', 'HEAD'], depot) != lock['depot_tools_revision']:
                errors.append('depot_tools revision differs from lock')
        except (OSError, subprocess.CalledProcessError):
            errors.append('Cannot verify depot_tools revision')
    else:
        errors.append('Run scripts/bootstrap_tools.py to install pinned depot_tools')
    if errors or not args.execute:
        print(json.dumps(report, indent=2))
        return 2 if errors else 0
    # Only this explicitly requested branch downloads. No cleanup of failures.
    workspace.mkdir(parents=True, exist_ok=True)
    marker = workspace / 'prepare-state.json'
    marker.write_text(json.dumps({**report, 'state': 'preparing'}, indent=2) + '\n')
    try:
        checkout(workspace / 'framework', lock['framework_revision'], lock['flutter_repository'])
        engine = workspace / 'engine'
        checkout(engine, lock['engine_revision'], lock['flutter_repository'])
        deps = (engine / 'DEPS').read_text()
        revision = re.search(r"'dart_revision':\s*'([a-f0-9]{40})'", deps)
        if not revision or revision.group(1) != lock['dart_revision']:
            raise RuntimeError('Engine DEPS Dart revision does not match lock')
        shutil.copyfile(engine / 'engine/scripts/standard.gclient', engine / '.gclient')
        # Streams build-tool progress; it is not a single-JSON CLI command.
        subprocess.run(['gclient', 'sync', '--no-history'], cwd=engine, check=True)
        dart = engine / 'engine/src/flutter/third_party/dart'
        if run(['git', 'rev-parse', 'HEAD'], dart) != lock['dart_revision']:
            raise RuntimeError('Synced Dart revision mismatch')
        report.update(executed=True, state='sources-ready-not-built')
        report['depot_tools_revision'] = lock['depot_tools_revision']
        marker.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        marker.write_text(json.dumps({**report, 'state': 'failed', 'error': str(error)}, indent=2) + '\n')
        print(f'Preparation failed; partial files retained in {workspace}: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
