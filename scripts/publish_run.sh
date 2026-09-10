#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HANDOFF="${1:-/workdir/agent-bench-smoke/RUN_HANDOFF.json}"
OWNER="${GITHUB_REPOSITORY_OWNER:-jposton96a}"
REPO="${GITHUB_REPOSITORY:-BenchBountyEvals}"
REMOTE="$OWNER/$REPO"

[[ -f "$HANDOFF" ]] || { echo "handoff not found: $HANDOFF" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
command -v gh >/dev/null || { echo "gh is required" >&2; exit 2; }

RUN_ID="$(jq -er '.runId' "$HANDOFF")"
STATUS="$(jq -er '.status' "$HANDOFF")"
SOURCE_DIR="$(jq -er '.sourceDir // .jobPath' "$HANDOFF")"
MANIFEST_PATH="$(jq -er '.manifestPath // .configPath // .resultPath' "$HANDOFF")"
HANDOFF_DIR="$(cd -- "$(dirname -- "$HANDOFF")" && pwd)"
[[ "$SOURCE_DIR" = /* ]] || SOURCE_DIR="$HANDOFF_DIR/$SOURCE_DIR"
[[ "$MANIFEST_PATH" = /* ]] || MANIFEST_PATH="$HANDOFF_DIR/$MANIFEST_PATH"
[[ -d "$SOURCE_DIR" ]] || { echo "sourceDir not found: $SOURCE_DIR" >&2; exit 2; }
[[ -f "$MANIFEST_PATH" ]] || { echo "manifestPath not found: $MANIFEST_PATH" >&2; exit 2; }

if [[ "$STATUS" != completed ]]; then
  [[ "${ALLOW_FAILED_PUBLISH:-0}" == 1 ]] || { echo "refusing status=$STATUS; explicit review required" >&2; exit 3; }
fi
if [[ "$RUN_ID" == *..* || "$RUN_ID" == */* || "$RUN_ID" == *" "* ]]; then
  echo "unsafe runId: $RUN_ID" >&2; exit 2
fi

STAGE="$ROOT_DIR/work/$RUN_ID"
rm -rf -- "$STAGE"
mkdir -p "$STAGE/bundle"
cp -a "$SOURCE_DIR/." "$STAGE/bundle/"
cp -a "$MANIFEST_PATH" "$STAGE/bundle/manifest.json"
cp -a "$HANDOFF" "$STAGE/bundle/RUN_HANDOFF.json"
rm -f "$STAGE/bundle/.env"
find "$STAGE/bundle" -type f \( -name '*.pem' -o -name '*.key' \) -delete
"$ROOT_DIR/scripts/secret_scan.sh" "$STAGE/bundle"
(cd "$STAGE/bundle" && find . -type f -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
tar -C "$STAGE/bundle" -cf "$STAGE/$RUN_ID.tar" .
if command -v zstd >/dev/null 2>&1; then
  zstd -T0 -19 --rm "$STAGE/$RUN_ID.tar" -o "$STAGE/$RUN_ID.tar.zst"
  BUNDLE="$STAGE/$RUN_ID.tar.zst"
else
  gzip -9 "$STAGE/$RUN_ID.tar"
  BUNDLE="$STAGE/$RUN_ID.tar.gz"
fi
SHA256="$(sha256sum "$BUNDLE" | awk '{print $1}')"
SIZE="$(stat -c '%s' "$BUNDLE")"

if ! gh repo view "$REMOTE" >/dev/null 2>&1; then
  gh repo create "$REMOTE" --public --description "Public evaluation metadata and trace bundles for BenchBounty" --source "$ROOT_DIR" --remote origin --push
else
  if ! git -C "$ROOT_DIR" remote get-url origin >/dev/null 2>&1; then
    git -C "$ROOT_DIR" remote add origin "https://github.com/$REMOTE.git"
  fi
fi

RELEASE_URL="$(gh release create "$RUN_ID" "$BUNDLE" --repo "$REMOTE" --title "$RUN_ID" --notes "Immutable raw artifacts for $RUN_ID. Compact normalized results are published in GitHub Pages.")"
ASSET_NAME="$(basename "$BUNDLE")"
ASSET_URL="https://github.com/$REMOTE/releases/download/$RUN_ID/$ASSET_NAME"

python3 - "$ROOT_DIR" "$HANDOFF" "$MANIFEST_PATH" "$RUN_ID" "$STATUS" "$ASSET_URL" "$SHA256" "$SIZE" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
handoff_path, manifest_path = pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
run_id, status, asset_url, sha256, size = sys.argv[4:8]
handoff = json.loads(handoff_path.read_text())
manifest = json.loads(manifest_path.read_text())
data = dict(manifest)
data.setdefault('schemaVersion', 1)
data['runId'] = run_id
data['status'] = status
data.setdefault('provenance', {'kind': 'agent_bench', 'measuredByAgentBench': True})
data['artifacts'] = {'rawBundle': {'url': asset_url, 'sha256': sha256, 'sizeBytes': int(size)}}
if handoff.get('normalizedResultPath'):
    p = pathlib.Path(handoff['normalizedResultPath'])
    if not p.is_absolute(): p = handoff_path.parent / p
    if p.exists():
        extra = json.loads(p.read_text())
        for k, v in extra.items():
            if k not in {'runId', 'status', 'artifacts'}: data[k] = v
run_dir = root / 'published' / 'runs' / run_id
run_dir.mkdir(parents=True, exist_ok=True)
(run_dir / 'manifest.json').write_text(json.dumps(data, indent=2, sort_keys=True) + '\\n')
(run_dir / 'result.json').write_text(json.dumps(data, indent=2, sort_keys=True) + '\\n')
PY

python3 - "$ROOT_DIR" <<'PY'
import datetime, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
runs, models, benchmarks = [], {}, {}
for p in sorted((root / 'published/runs').glob('*/result.json')):
    d = json.loads(p.read_text())
    rid = d['runId']; model = d.get('model') or {}; benchmark = d.get('benchmark') or {}
    runs.append({'runId': rid, 'status': d.get('status'), 'url': f'runs/{rid}/result.json'})
    if model.get('id'):
        models.setdefault(model['id'], {'id': model['id'], 'name': model.get('name', model['id']), 'runIds': []})['runIds'].append(rid)
    if benchmark.get('id'):
        benchmarks.setdefault(benchmark['id'], {'id': benchmark['id'], 'name': benchmark.get('name', benchmark['id']), 'runIds': []})['runIds'].append(rid)
for obj, folder in ((models, 'models'), (benchmarks, 'benchmarks')):
    for ident, item in obj.items():
        item['runCount'] = len(item['runIds']); item['url'] = f'{folder}/{ident}.json'
        (root / 'published' / folder / f'{ident}.json').write_text(json.dumps(item, indent=2, sort_keys=True) + '\\n')
index = {'schemaVersion': 1, 'generatedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'dataStatus': 'real', 'runs': runs, 'models': list(models.values()), 'benchmarks': list(benchmarks.values())}
(root / 'published/index.json').write_text(json.dumps(index, indent=2, sort_keys=True) + '\\n')
PY

git -C "$ROOT_DIR" add README.md .gitignore schemas docs scripts published
git -C "$ROOT_DIR" commit -m "Publish evaluation $RUN_ID" || true
git -C "$ROOT_DIR" push -u origin HEAD
echo "published $RUN_ID"
echo "release: $RELEASE_URL"
echo "asset: $ASSET_URL"
