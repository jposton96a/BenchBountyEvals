#!/usr/bin/env python3
"""Exercise the new scoring validator in an isolated local JSON fixture."""
import copy
import json
import os
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
import sys
sys.path.insert(0, str(ROOT / "scripts"))
from config_id import config_id


def validate(root, doc):
    path = root / "published" / "runs" / "fixture" / "result.json"
    path.write_text(json.dumps(doc))
    return subprocess.run([str(ROOT / "scripts" / "validate_json.sh"), str(root)], capture_output=True, text=True)


def main():
    with tempfile.TemporaryDirectory(dir=os.environ.get("KIROCREW_SCRATCH")) as temp:
        root = pathlib.Path(temp)
        (root / "scripts").mkdir()
        (root / "published" / "models").mkdir(parents=True)
        (root / "published" / "runs" / "fixture").mkdir(parents=True)
        shutil.copy2(ROOT / "scripts" / "config_id.py", root / "scripts" / "config_id.py")
        shutil.copy2(ROOT / "published" / "models" / "qwen3.8-27b.json", root / "published" / "models" / "qwen3.8-27b.json")
        model = json.loads((ROOT / "published" / "models" / "qwen3.8-27b.json").read_text())
        quant = next(q for q in model["quants"] if q["id"] == "bartowski-q4_k_m")
        harness = {"id": "terminus-2", "agentVersion": "2.0.0",
                   "settings": {"maxTurns": 50, "agentTimeout": "task", "verifierTimeout": "task",
                                "scoringPolicy": "timeout-fails-v1"}}
        thinking = {"mode": "on", "effort": "medium"}
        doc = {"schemaVersion": 2, "provenance": {"kind": "agent_bench"}, "modelId": model["id"],
               "quantId": quant["id"], "quantization": {"format": "gguf", "level": "Q4_K_M"},
               "thinking": thinking, "harness": harness, "configId": config_id(model["id"], quant, thinking, harness),
               "result": {"scoringPolicy": "timeout-fails-v1", "nTasks": 1, "nPassed": 0},
               "tasks": [{"taskName": "fixture", "outcome": "failed", "reward": 0.0,
                          "rawVerifierReward": 1.0, "timedOut": True, "verifierTimedOut": False,
                          "outputTokens": 300, "generationTokensPerSec": 0.5,
                          "llmRequestWallSec": 600.0,
                          "generationRateDenominator": "agent phase wall time",
                          "timeout": {"phase": "agent", "effectiveLimitSec": 900.0,
                                      "phaseDurationSec": 600.0}}]}
        good = validate(root, doc)
        assert good.returncode == 0, good.stderr
        bad = copy.deepcopy(doc)
        bad["tasks"][0]["outcome"] = "passed"
        rejected = validate(root, bad)
        assert rejected.returncode != 0 and "timeout must be a scored failure" in rejected.stderr, rejected.stderr
        print("timeout-fails-v1 fixture accepted; scoring a timeout as passed rejected")


if __name__ == "__main__":
    main()
