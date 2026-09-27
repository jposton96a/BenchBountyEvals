# BenchBountyEvals

Public, immutable evaluation metadata and links for BenchBounty.

The `published/` directory is the small static data contract consumed by the
separate web UI. Complete run traces are published as compressed assets on a
GitHub Release for the corresponding run, not committed to the repository.

## Contract

- `published/index.json` is the discovery document.
- `published/models/<model-id>.json` contains model-level run references and
  aggregates.
- `published/benchmarks/<benchmark-id>.json` contains benchmark-level run
  references.
- `published/runs/<run-id>/result.json` contains the normalized exact-run
  result and a link to its complete Release bundle.
- `published/runs/<run-id>/manifest.json` records the exact configuration and
  provenance.

Every run is immutable. A retry or corrected measurement gets a new run ID.
Scores are never synthesized from missing artifacts. Smoke tests are marked
`provenance.kind: demo` and are not benchmark claims.

## Raw artifacts

The Release asset is `<run-id>.tar.zst` (or `<run-id>.tar.gz` when the host has
no zstd binary; deterministic numbered parts are used when larger than
GitHub's per-asset limit). It contains the original Harbor job,
trial traces, stdout/stderr, normalized outputs, environment inventory, and a
SHA-256 manifest. Secrets and credentials are excluded before publication.

## Local validation

```bash
./scripts/validate_json.sh
```

## Publishing a run

```bash
PUBLISH_MODE=local ./scripts/publish_run.sh /path/to/RUN_HANDOFF.json
```

`local` bundles, scans and writes `published/` JSON, then commits locally; the
bundle stays in `work/<run-id>/` and `rawBundle.uploaded` is `false`. The
default `remote` mode also creates the public repo, the Release, pushes and
enables Pages. `index.json` `dataStatus` is `real` only when every listed run
has `provenance.kind: agent_bench`; `realRunCount` counts those runs.
