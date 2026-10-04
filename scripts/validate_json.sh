#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT_DIR" <<'PY'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
files = sorted(root.glob('published/**/*.json')) + sorted(root.glob('schemas/*.json'))
QUANT_LEVELS = {'full', 'bf16', 'fp16', 'fp8', 'int8', 'fp6', 'fp4', 'int4'}
# llama.cpp GGUF quant types (Q4_K_M, Q6_K, Q8_0, IQ4_XS, ...), recorded verbatim with format 'gguf'.
GGUF_LEVEL = re.compile(r'^I?Q[1-8](_[0-9A-Z]+)*$')
THINKING_MODES = {'unsupported', 'off', 'on'}


def check_qualifiers(path, run):
    if run.get('schemaVersion') != 2 or (run.get('provenance') or {}).get('kind') != 'agent_bench':
        return
    quant, thinking = run.get('quantization') or {}, run.get('thinking') or {}
    level = quant.get('level')
    gguf = quant.get('format') == 'gguf' and isinstance(level, str) and GGUF_LEVEL.match(level)
    if level not in QUANT_LEVELS and not gguf:
        sys.exit(f'{path}: quantization.level must be one of {sorted(QUANT_LEVELS)}, or a GGUF type with format gguf')
    if thinking.get('mode') not in THINKING_MODES:
        sys.exit(f'{path}: thinking.mode must be one of {sorted(THINKING_MODES)}')
    if (thinking['mode'] == 'on') != bool(thinking.get('effort')):
        sys.exit(f'{path}: thinking.effort is required when mode is on, and only then')


for path in files:
    with path.open() as f:
        doc = json.load(f)
    if path.name in ('manifest.json', 'result.json') and path.parent.parent.name == 'runs':
        check_qualifiers(path.relative_to(root), doc)
    print(path.relative_to(root))
print(f'validated {len(files)} JSON files')
PY

