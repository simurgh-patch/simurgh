#!/usr/bin/env python3
"""Inventory prepared M0 sources and license candidates; not a license audit."""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def parse_entries(text):
    tree = ast.parse(text)
    if (len(tree.body) != 1 or not isinstance(tree.body[0], ast.Assign)
            or len(tree.body[0].targets) != 1
            or not isinstance(tree.body[0].targets[0], ast.Name)
            or tree.body[0].targets[0].id != 'entries'):
        raise ValueError('Expected a single literal entries mapping')
    entries = ast.literal_eval(tree.body[0].value)
    if not isinstance(entries, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in entries.items()):
        raise ValueError('Invalid dependency entries')
    return entries


def inside(root, relative):
    path = root / relative
    if Path(relative).is_absolute() or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError(f'Path escapes source root: {relative}')
    return path


def git(path, *args):
    return subprocess.check_output(['git', '-C', str(path), *args]).decode('utf-8').strip()


def license_candidate(path):
    return bool(re.match(r'^(LICENSE|LICENCE|COPYING|COPYRIGHT|NOTICE)(?:[._-].*|$)', Path(path).name, re.I))


def repository_inventory(path, expected):
    if Path(git(path, 'rev-parse', '--show-toplevel')).resolve() != path.resolve():
        raise ValueError('Dependency is not an independent checkout')
    revision = git(path, 'rev-parse', 'HEAD')
    errors = []
    expected_commit = git(path, 'rev-parse', expected + '^{commit}')
    if revision != expected_commit:
        errors.append('revision_mismatch')
    if git(path, 'status', '--porcelain', '--untracked-files=normal'):
        errors.append('dirty_checkout')
    # Git's NUL format keeps spaces/newlines in filenames unambiguous.
    tracked = subprocess.check_output(['git', '-C', str(path), 'ls-files', '-z']).decode('utf-8').split('\0')
    licenses = []
    for name in sorted(filter(license_candidate, filter(None, tracked))):
        file = inside(path, name)
        if file.is_file():
            licenses.append({'path': name, 'sha256': digest(file), 'size': file.stat().st_size})
    # Detect concurrent edits, including files hashed earlier in this scan.
    if git(path, 'rev-parse', 'HEAD') != revision or git(path, 'status', '--porcelain', '--untracked-files=normal'):
        errors.append('source_changed_or_dirty_after_scan')
    return {'revision': revision, 'expected_revision': expected, 'expected_commit': expected_commit, 'errors': errors,
            'license_candidates': licenses, 'license_review': 'manual_review_required'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-root', type=Path, required=True)
    args = parser.parse_args()
    workspace = args.build_root.expanduser().resolve()
    engine = workspace / 'engine'
    lock = json.loads((ROOT / 'toolchain.lock.json').read_text())
    marker = json.loads((workspace / 'prepare-state.json').read_text())
    if marker.get('state') != 'sources-ready-not-built':
        raise ValueError('Prepare sources before inventory')
    for key in ('framework_revision', 'engine_revision', 'dart_revision', 'depot_tools_revision'):
        if marker.get(key) != lock[key]:
            raise ValueError(f'Preparation differs from lock: {key}')
    parent = ROOT / 'output/source-inventories'
    parent.mkdir(parents=True, exist_ok=True)
    destination = Path(tempfile.mkdtemp(prefix='inventory-', dir=parent))
    report = {'schema_version': 1, 'lock': lock, 'scope': 'gclient dependencies, framework and bootstrap depot_tools',
              'license_audit_complete': False, 'm0_passed': False, 'components': [], 'errors': []}
    try:
        entries = parse_entries((engine / '.gclient_entries').read_text())
        actual_file = destination / 'actual.json'
        with (destination / 'gclient.log').open('x') as log:
            subprocess.run([str(ROOT / '.tools/depot_tools/gclient'), 'revinfo', '--actual', '--output-json', str(actual_file)],
                           cwd=engine, env={**os.environ, 'DEPOT_TOOLS_UPDATE': '0'}, check=True,
                           stdout=log, stderr=subprocess.STDOUT)
        actual = json.loads(actual_file.read_text())
        if set(actual) != set(entries):
            raise ValueError('Actual dependencies differ from prepared dependency set')
        for name, requested in sorted(entries.items()):
            resolved = actual[name]
            path_part = name.split(':', 1)[0]
            checkout = inside(engine, path_part)
            component = {'path': name, 'requested_source': requested, 'resolved_source': resolved}
            if ':' in name:
                component.update(kind='cipd', license_review='not_scanned_shared_package_directory')
            else:
                expected = lock['engine_revision'] if name == '.' else requested.rpartition('@')[2]
                if not re.fullmatch(r'[a-f0-9]{40}', expected):
                    raise ValueError(f'Unpinned Git dependency: {name}')
                component.update(kind='git', **repository_inventory(checkout, expected))
                if component['revision'] != resolved.get('rev'):
                    component['errors'].append('gclient_actual_revision_mismatch')
                report['errors'].extend(f'{name}: {error}' for error in component['errors'])
            report['components'].append(component)
        for name, path, key in [('framework', workspace / 'framework', 'framework_revision'),
                                ('bootstrap_depot_tools', ROOT / '.tools/depot_tools', 'depot_tools_revision')]:
            component = {'path': name, 'kind': 'git', **repository_inventory(path, lock[key])}
            report['components'].append(component)
            report['errors'].extend(f'{name}: {error}' for error in component['errors'])
        report['state'] = 'source_inventory_complete' if not report['errors'] else 'failed'
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        report.update(state='failed')
        report['errors'].append(str(error))
    (destination / 'inventory.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'state': report['state'], 'manifest': str(destination / 'inventory.json'),
                      'components': len(report['components']), 'errors': report['errors']}))
    return 2 if report['errors'] else 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(json.dumps({'state': 'failed', 'error': str(error)}))
        raise SystemExit(2)
