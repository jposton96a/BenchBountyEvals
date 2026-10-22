#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
python3 - "$ROOT_DIR" <<'PY'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(root / 'scripts'))
from config_id import config_id
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


MODEL_KEYS = {'id', 'name', 'hfRepo', 'baseModelId', 'vendor', 'releaseDate', 'openWeights', 'nativePrecision',
              'referenceQuantId', 'thinking', 'quants', 'verified'}


def check_model(path, model):
    missing = MODEL_KEYS - model.keys()
    if missing:
        sys.exit(f'{path}: model record missing {sorted(missing)}')
    if path.stem != model['id']:
        sys.exit(f'{path}: file name must be <id>.json')
    ids = [q['id'] for q in model['quants']]
    if len(ids) != len(set(ids)):
        sys.exit(f'{path}: quant ids must be unique')
    if model['referenceQuantId'] is not None and model['referenceQuantId'] not in ids:
        sys.exit(f'{path}: referenceQuantId {model["referenceQuantId"]} is not a quant')
    for q in model['quants']:
        if not {'id', 'format', 'scheme'} <= q.keys():
            sys.exit(f'{path}: quant {q.get("id")} needs id, format and scheme')
    t = model['thinking']
    if not t['modes'] or not set(t['modes']) <= {'off', 'on'}:
        sys.exit(f'{path}: thinking.modes must be a non-empty subset of off/on')
    if t['efforts'] is not None and ('on' not in t['modes'] or not t['efforts']):
        sys.exit(f'{path}: thinking.efforts needs mode on, and is null or a non-empty list')


def check_config(path, run, models):
    """Measured runs name a model record and quant; thinking and configId must agree with them."""
    model = models.get(run.get('modelId'))
    if not model:
        sys.exit(f'{path}: modelId {run.get("modelId")!r} has no published/models record')
    quant = next((q for q in model['quants'] if q['id'] == run.get('quantId')), None)
    if not quant:
        sys.exit(f'{path}: quantId {run.get("quantId")!r} is not a quant of {model["id"]}')
    if quant['format'] != 'api' and not (quant.get('revision') and quant.get('files')):
        sys.exit(f'{path}: quant {quant["id"]} has a measured run, so it needs revision and files[].sha256')
    served = ((run.get('serving') or {}).get('weights') or {}).get('sha256')
    if served and served not in {f['sha256'] for f in quant.get('files') or []}:
        sys.exit(f'{path}: serving.weights.sha256 does not match quant {quant["id"]}')
    thinking, allowed = run.get('thinking') or {}, model['thinking']
    if thinking.get('mode') not in allowed['modes']:
        sys.exit(f'{path}: thinking.mode {thinking.get("mode")!r} not in {model["id"]} modes {allowed["modes"]}')
    effort = thinking.get('effort')
    if effort is not None and (thinking['mode'] != 'on' or effort not in (allowed['efforts'] or [])):
        sys.exit(f'{path}: thinking.effort {effort!r} not allowed by {model["id"]}')
    if not (run.get('harness') or {}).get('id'):
        sys.exit(f'{path}: harness.id is required')
    expected = config_id(model['id'], quant, thinking, run['harness'])
    if run.get('configId') != expected:
        sys.exit(f'{path}: configId {run.get("configId")} != {expected}')


def check_scoring(path, run):
    """Legacy runs are immutable; validate the new timeout policy when declared."""
    result = run.get('result') or {}
    if result.get('scoringPolicy') != 'timeout-fails-v1':
        if result.get('scoringPolicy') is not None:
            sys.exit(f'{path}: unknown scoring policy')
        return
    if (run.get('harness') or {}).get('settings', {}).get('scoringPolicy') != 'timeout-fails-v1':
        sys.exit(f'{path}: scoring policy must be part of harness settings/configId')
    tasks = run.get('tasks')
    if tasks is None:
        return  # manifest has no trial list; result.json carries it
    if len(tasks) > result.get('nTasks', -1):
        sys.exit(f'{path}: trial count exceeds result.nTasks')
    for task in tasks:
        timed_out = task.get('timedOut') or task.get('verifierTimedOut')
        if task.get('reward') is not None and task.get('rawVerifierReward') is None and not timed_out:
            sys.exit(f'{path}: {task.get("taskName")}: raw verifier reward is required')
        if timed_out:
            timeout = task.get('timeout') or {}
            expected_phase = 'agent' if task.get('timedOut') else 'verifier'
            if task.get('outcome') != 'failed' or task.get('reward') != 0.0:
                sys.exit(f'{path}: {task.get("taskName")}: timeout must be a scored failure')
            if timeout.get('phase') != expected_phase or not (timeout.get('effectiveLimitSec') or timeout.get('effectiveLimitReason')):
                sys.exit(f'{path}: {task.get("taskName")}: missing effective timeout or reason')
            if timeout.get('phaseDurationSec') is None and not timeout.get('phaseDurationReason'):
                sys.exit(f'{path}: {task.get("taskName")}: missing timeout duration or reason')
            if task.get('outputTokens') is None and not task.get('outputTokensUnavailableReason'):
                sys.exit(f'{path}: {task.get("taskName")}: missing token-count reason')
        if task.get('generationTokensPerSec') is not None and not task.get('generationRateDenominator'):
            sys.exit(f'{path}: {task.get("taskName")}: missing generation-rate denominator')
        if task.get('generationTokensPerSec') is not None and not (task.get('llmRequestWallSec') or 0) > 0:
            sys.exit(f'{path}: {task.get("taskName")}: missing positive LLM request duration')
    if result.get('nPassed') != sum(t.get('outcome') == 'passed' for t in tasks):
        sys.exit(f'{path}: passed count does not match trials')


models = {}
for path in sorted(root.glob('published/models/*.json')):
    model = json.loads(path.read_text())
    check_model(path.relative_to(root), model)
    models[model['id']] = model

for path in files:
    with path.open() as f:
        doc = json.load(f)
    if path.name in ('manifest.json', 'result.json') and path.parent.parent.name == 'runs':
        check_qualifiers(path.relative_to(root), doc)
        if (doc.get('provenance') or {}).get('kind') == 'agent_bench':
            check_config(path.relative_to(root), doc, models)
            check_scoring(path.relative_to(root), doc)
    print(path.relative_to(root))
print(f'validated {len(files)} JSON files')
PY
