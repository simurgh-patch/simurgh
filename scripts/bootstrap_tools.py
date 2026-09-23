#!/usr/bin/env python3
"""Install pinned depot_tools inside this project, without engine dependencies."""
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    lock = json.loads((ROOT / 'toolchain.lock.json').read_text())
    target = ROOT / '.tools/depot_tools'
    revision = lock['depot_tools_revision']
    if not target.exists():
        target.mkdir(parents=True)
        for command in [
            ['git', 'init'],
            ['git', 'remote', 'add', 'upstream', lock['depot_tools_repository']],
            ['git', 'fetch', '--depth=1', 'upstream', revision],
            ['git', 'checkout', '--detach', 'FETCH_HEAD'],
        ]:
            subprocess.run(command, cwd=target, check=True)
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=target, text=True).strip()
    if actual != revision:
        raise RuntimeError('Existing depot_tools revision mismatch; no overwrite performed')
    dirty = subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=target, text=True)
    if dirty.strip():
        raise RuntimeError('depot_tools has tracked modifications; refusing to run it')
    env = {**os.environ, 'DEPOT_TOOLS_UPDATE': '0'}
    subprocess.run([str(target / 'gclient'), '--help'], env=env, check=True, stdout=subprocess.PIPE)
    print(json.dumps({'depot_tools_revision': actual, 'path': str(target)}))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
