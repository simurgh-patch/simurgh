#!/usr/bin/env python3
"""Apply or verify the exact, reviewed Dart runtime patch set; never reset sources."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PATCHES = ROOT / 'runtime/patches'
DART_SOURCE = ROOT / '.engine-workspace/engine/engine/src/flutter/third_party/dart'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(source, *args):
    return subprocess.check_output(['git', *args], cwd=source)


def contained(root, relative):
    path = root / relative
    if Path(relative).is_absolute() or '..' in Path(relative).parts or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError(f'Patch path escapes source root: {relative}')
    return path


def verify_runtime_sources(source=DART_SOURCE, patch_dir=PATCHES, apply=False):
    source, patch_dir = Path(source), Path(patch_dir)
    manifest_bytes = (patch_dir / 'manifest.json').read_bytes()
    manifest = json.loads(manifest_bytes)
    if manifest['schema'] != 1:
        raise ValueError('Unsupported runtime patch manifest schema')
    revision = git(source, 'rev-parse', 'HEAD').decode().strip()
    if revision != manifest['dart_revision']:
        raise ValueError('Runtime patch set targets a different Dart revision')
    expected = {}
    patch_paths = []
    for patch in manifest['patches']:
        path = contained(patch_dir, patch['path'])
        if digest(path.read_bytes()) != patch['sha256']:
            raise ValueError(f'Runtime patch digest mismatch: {path}')
        patch_paths.append(path.resolve())
        for relative, hashes in patch['files'].items():
            contained(source, relative)
            if relative in expected:
                raise ValueError('Overlapping runtime patches need an explicit composed patch')
            base = git(source, 'show', f'{revision}:{relative}')
            if digest(base) != hashes['base_sha256']:
                raise ValueError(f'Runtime base source digest mismatch: {relative}')
            expected[relative] = hashes
    changed = set(filter(None, git(source, 'diff', '--name-only', '-z', 'HEAD').decode().split('\0')))
    if changed - expected.keys():
        raise ValueError(f'Unrecorded runtime source modifications: {sorted(changed - expected.keys())}')
    if git(source, 'diff', '--cached', '--name-only').strip():
        raise ValueError('Staged source changes are not managed by runtime patch tooling')
    states = []
    for relative, hashes in expected.items():
        actual = digest(contained(source, relative).read_bytes())
        if actual == hashes['patched_sha256']:
            states.append('patched')
        elif actual == hashes['base_sha256']:
            states.append('base')
        else:
            raise ValueError(f'Runtime source differs from both base and reviewed patch: {relative}')
    if states and set(states) != {'patched'}:
        if not apply:
            raise ValueError('Runtime patch set not applied; run scripts/runtime_sources.py --apply')
        if set(states) != {'base'} or changed:
            raise ValueError('Partially applied patch set; preserve sources and inspect manually')
        subprocess.run(['git', 'apply', '--check', *map(str, patch_paths)], cwd=source, check=True)
        subprocess.run(['git', 'apply', *map(str, patch_paths)], cwd=source, check=True)
        return verify_runtime_sources(source, patch_dir)
    return {'runtime_patchset_sha256': digest(manifest_bytes),
            'runtime_source_files': {relative: hashes['patched_sha256'] for relative, hashes in expected.items()}}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true', help='Apply only to a clean pinned base; never reset or overwrite unrelated edits')
    args = parser.parse_args()
    print(json.dumps(verify_runtime_sources(apply=args.apply), indent=2))
