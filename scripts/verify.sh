#!/bin/sh
set -eu
PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT"
DART_BIN=${SIMURGH_DART:-dart}
if [ -n "${SIMURGH_FLUTTER_SDK:-}" ]; then
  FLUTTER_BIN="$SIMURGH_FLUTTER_SDK/bin/flutter"
else
  FLUTTER_BIN=flutter
fi
"$DART_BIN" analyze
"$DART_BIN" test
python3 -m unittest discover -s test -p '*_test.py'
cd examples/runtime_probe
"$FLUTTER_BIN" analyze
"$FLUTTER_BIN" test --reporter expanded
