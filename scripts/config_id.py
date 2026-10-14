#!/usr/bin/env python3
"""configId: a hash of the four config axes (eval-config-schema.md, "Configs and pooling").

usage: config_id.py <manifest.json>   prints the configId for a run

The quant is identified by its file sha256s (API quants have none, so by modelId/quantId).
Harness version is harness.agentVersion: harness.version predates the schema and holds
the Harbor framework version. Serving and hardware are not part of a config.
agent-bench-smoke/scripts/make-handoff.py carries a copy of config_id(); the validator
recomputes every run's configId, so the two cannot drift silently.
"""
import hashlib
import json
import pathlib
import sys


def config_id(model_id, quant, thinking, harness):
    shas = sorted(f["sha256"] for f in quant.get("files") or [])
    axes = {
        "model": model_id,
        "quant": shas or f"{model_id}/{quant['id']}",
        "thinking": {"mode": thinking.get("mode"), "effort": thinking.get("effort")},
        "harness": {"id": harness["id"], "version": harness.get("agentVersion"), "settings": harness.get("settings") or {}},
    }
    canonical = json.dumps(axes, sort_keys=True, separators=(",", ":"))
    return "cfg-" + hashlib.sha256(canonical.encode()).hexdigest()[:16]


def load_quant(models_dir, model_id, quant_id):
    model = json.loads((pathlib.Path(models_dir) / f"{model_id}.json").read_text())
    return next(q for q in model["quants"] if q["id"] == quant_id)


if __name__ == "__main__":
    run = json.loads(pathlib.Path(sys.argv[1]).read_text())
    models = pathlib.Path(__file__).resolve().parent.parent / "published" / "models"
    print(config_id(run["modelId"], load_quant(models, run["modelId"], run["quantId"]), run["thinking"], run["harness"]))
