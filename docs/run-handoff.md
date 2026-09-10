# Runner handoff

The executor must write `/workdir/agent-bench-smoke/RUN_HANDOFF.json` only
after Harbor has stopped and all artifacts are durable. Paths may be absolute
or relative to the handoff file's directory. The minimum shape is:

```json
{
  "schemaVersion": 1,
  "runId": "20260910-qwen36-35b-openrouter-smoke-001",
  "status": "completed",
  "sourceDir": "jobs/smoke-qwen35-openrouter",
  "manifestPath": "jobs/smoke-qwen35-openrouter/manifest.json",
  "normalizedResultPath": null,
  "taskResultsPath": null,
  "model": {"id": "qwen3.6-35b", "name": "Qwen3.6 35B"},
  "benchmark": {"id": "harbor-smoke", "name": "Harbor smoke task"},
  "notes": "One-task pipeline smoke test; not a benchmark score."
}
```

The publisher rejects a missing source directory, missing manifest, or an
ambiguous failed/partial status. A failed run can be published only after an
explicit human decision and a deliberate override; it must remain visibly
failed and contain failure-stage/error details.

