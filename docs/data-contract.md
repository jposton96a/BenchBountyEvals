# Static publication contract

The canonical public origin is the GitHub Pages site for this repository:

```text
https://<owner>.github.io/BenchBountyEvals/published/index.json
```

The UI must start at `index.json`, then fetch only the documents it needs. The
exact-run document is the source of truth for a score. It contains a stable
Release URL for the complete raw bundle. Release assets are immutable; the UI
can expose them as a full-trace download.

## Index shape

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-09-10T00:00:00Z",
  "dataStatus": "real",
  "runs": [{"runId": "...", "status": "completed", "url": "runs/.../result.json"}],
  "models": [{"id": "...", "name": "...", "url": "models/...json", "runCount": 1}],
  "benchmarks": [{"id": "...", "name": "...", "url": "benchmarks/...json", "runCount": 1}]
}
```

`dataStatus` is `real` only when all listed results are measured runs. A
repository containing only fixtures or smoke/demo data must say `demo`.

## Run shape

`published/runs/<run-id>/result.json` retains the normalized score, task-level
facts, exact configuration, timing/cost fields when available, status, failure
details when applicable, and:

```json
"artifacts": {
  "rawBundle": {
    "url": "https://github.com/<owner>/BenchBountyEvals/releases/download/<run-id>/<run-id>.tar.zst",
    "sha256": "...",
    "sizeBytes": 1234
  }
}
```

Unknown or unavailable fields are omitted or `null`; they are never guessed.

## Configuration qualifiers

From `schemaVersion: 2`, every Agent Bench run must record both qualifiers;
`scripts/validate_json.sh` rejects one that does not. Version 1 runs predate
this rule and may leave them `null`.

```json
"quantization": {"level": "fp8", "servedPrecision": "fp8", "nativePrecision": "bf16"},
"thinking": {"mode": "on", "effort": "default"}
```

- `quantization.level` is `full` when the model was served at its checkpoint's
  native precision, otherwise the served precision (`fp8`, `fp4`, `int4`, ...).
  Self-hosted GGUF runs record the llama.cpp quant type verbatim (`Q4_K_M`,
  `Q6_K`, `Q8_0`, ...) together with `"format": "gguf"`, since k-quants mix
  bit widths and have no faithful match among the precision names.
- `thinking.mode` is `unsupported` for models without a thinking mode, else
  `off` or `on`. `effort` is set only when `mode` is `on`; `default` means
  thinking was enabled without an explicit effort.

## Config axes (model records)

Measured runs also name their configuration by reference
(`eval-config-schema.md` in the spareflops notes is the design):

```json
"modelId": "qwen3.8-27b",
"quantId": "bartowski-q4_k_m",
"configId": "cfg-e000498e8d58f88a",
"thinking": {"mode": "off", "effort": null},
"harness": {"id": "terminus-2", "agentVersion": "2.0.0", "framework": "harbor@0.22.0",
            "settings": {"maxTurns": 50, "agentTimeout": "task", "verifierTimeout": "task"}}
```

- `modelId` and `quantId` must exist in `published/models/<modelId>.json`, and
  `serving.weights.sha256` must be one of the quant's `files[].sha256`.
- `thinking.mode` must be in the model's `thinking.modes`; `effort` is `null`
  (model default) or one of its `thinking.efforts`.
- The harness version is `harness.agentVersion`. `harness.version` predates
  this schema and holds the Harbor version; runs are immutable, so it stays.
- `configId` is computed by `scripts/config_id.py` from the four axes
  (model, quant file sha256s, thinking, harness id/agentVersion/settings).
  Serving and hardware are provenance, not config. Runs with the same
  `configId` on the same benchmark version are pooled as repeat trials.
- `validate_json.sh` checks all of the above.
