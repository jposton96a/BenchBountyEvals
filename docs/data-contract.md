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
- `thinking.mode` is `unsupported` for models without a thinking mode, else
  `off` or `on`. `effort` is set only when `mode` is `on`; `default` means
  thinking was enabled without an explicit effort.
