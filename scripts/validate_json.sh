#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT_DIR" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = sorted(root.glob('published/**/*.json')) + sorted(root.glob('schemas/*.json'))
for path in files:
    with path.open() as f:
        json.load(f)
    print(path.relative_to(root))
print(f'validated {len(files)} JSON files')
PY

