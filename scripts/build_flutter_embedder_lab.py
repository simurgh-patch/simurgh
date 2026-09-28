#!/usr/bin/env python3
"""Build the restricted host AOT embedder in the already verified dynamic workspace.

Default is read-only. This extends the existing GN output without regenerating
its configuration or replacing the verified runtime tools. No device acceptance.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from aot_lab import ROOT, ENGINE, DYNAMIC, NINJA, RUNTIME_MANIFEST, source_identity, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--ignore-space-check', action='store_true')
    parser.add_argument('--output', type=Path, help='Fresh directory for build evidence')
    args = parser.parse_args()
    lock = json.loads((ROOT / 'toolchain.lock.json').read_text())
    identity = source_identity()
    provenance = json.loads(RUNTIME_MANIFEST.read_text())
    if any(provenance.get(key) != value for key, value in identity.items()):
        raise ValueError('Prepared dynamic runtime source identity mismatch')
    for name in ['args.gn', 'dartaotruntime', 'gen_snapshot']:
        if sha(DYNAMIC / name) != provenance['artifacts'][name]:
            raise ValueError(f'Prepared dynamic runtime changed: {name}')
    gn = (DYNAMIC / 'args.gn').read_text()
    if 'dart_dynamic_modules = true' not in gn or 'flutter_runtime_mode = "release"' not in gn:
        raise ValueError('Expected the prepared Release dynamic-module GN output')
    command = [str(NINJA), '-j2', '-C', str(DYNAMIC), 'libflutter_engine.dylib']
    free = shutil.disk_usage(DYNAMIC).free
    errors = []
    if free < lock['engine_workspace_min_free_bytes'] and not args.ignore_space_check:
        errors.append('Insufficient build space; explicit --ignore-space-check is required')
    if args.output and args.output.exists():
        errors.append('Evidence output already exists; refusing to overwrite')
    plan = {'kind': 'experimental-host-flutter-embedder-build', 'identity': identity,
            'runtime_provenance': provenance, 'command': command, 'errors': errors,
            'free_bytes': free, 'space_check_overridden': args.ignore_space_check,
            'engine_executed': False, 'device_accepted': False, 'script_sha256': sha(__file__)}
    if errors or not args.execute:
        print(json.dumps(plan, indent=2))
        return 2 if errors else 0
    if args.output:
        destination = args.output.resolve()
        destination.mkdir(parents=True, exist_ok=False)
    else:
        parent = ROOT / 'output/engine-builds'
        parent.mkdir(parents=True, exist_ok=True)
        destination = Path(tempfile.mkdtemp(prefix='host-flutter-embedder-', dir=parent))
    record = {**plan, 'state': 'building', 'started_at': datetime.now(timezone.utc).isoformat(),
              'engine_existed_before': (DYNAMIC / 'libflutter_engine.dylib').exists()}
    manifest = destination / 'build.json'
    manifest.write_text(json.dumps(record, indent=2) + '\n')
    env = {**os.environ, 'DEPOT_TOOLS_UPDATE': '0',
           'PATH': str(ROOT / '.tools/depot_tools') + os.pathsep + os.environ.get('PATH', '')}
    for variable in ['CPATH', 'LIBRARY_PATH', 'SDKROOT']:
        env.pop(variable, None)
    with (destination / 'build.log').open('w') as log:
        record['exit_code'] = subprocess.run(command, cwd=ENGINE, env=env, stdout=log,
                                             stderr=subprocess.STDOUT).returncode
    record.update(finished_at=datetime.now(timezone.utc).isoformat(),
                  identity_unchanged=identity == source_identity(),
                  runtime_artifacts_unchanged=all(sha(DYNAMIC / name) == digest
                                                  for name, digest in provenance['artifacts'].items()))
    artifact = DYNAMIC / 'libflutter_engine.dylib'
    valid = record['exit_code'] == 0 and record['identity_unchanged'] and \
        record['runtime_artifacts_unchanged'] and artifact.is_file()
    record['state'] = 'compiled-not-executed' if valid else 'failed'
    if artifact.is_file():
        record['engine_sha256'] = sha(artifact)
    manifest.write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'state': record['state'], 'manifest': str(manifest)}))
    return 0 if valid else 2


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(2)
