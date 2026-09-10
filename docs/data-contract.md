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
