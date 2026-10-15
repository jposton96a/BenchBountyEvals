#!/usr/bin/env python3
"""Offline test for sync-requests.py: parse and aggregate fixture issues (no network)."""
import importlib.util
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("sync_requests", HERE / "sync-requests.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

FENCE = "```"


def block(**axes):
    return f"{FENCE}agentbench-request\n" + "".join(f"{k}: {v}\n" for k, v in axes.items()) + f"{FENCE}\n"


def issue(number, title, body, votes=0, comments=0):
    return {"number": number, "title": title, "body": body, "state": "open", "comments": comments,
            "html_url": f"https://github.com/o/r/issues/{number}", "created_at": "2026-10-14T00:00:00Z",
            "user": {"login": "alice"}, "reactions": {"+1": votes}}


def comment(cid, body, votes=0, login="bob"):
    return {"id": cid, "body": body, "html_url": f"https://github.com/o/r/issues/1#issuecomment-{cid}",
            "created_at": "2026-10-14T01:00:00Z", "user": {"login": login}, "reactions": {"+1": votes}}


def main():
    models = sync.load_models()
    q38 = sync.build_request(
        issue(1, "Eval request: qwen3.8-27b",
              block(model="qwen3.8-27b", quant="bartowski-q4_k_m", thinking="on  # with effort later",
                    harness="any", benchmark="terminal-bench@2.0"), votes=4, comments=2),
        [comment(10, "me too\n" + block(model="qwen3.8-27b", quant="any", thinking="on:xhigh")
                 + "and\n" + block(model="qwen3.8-27b", quant="unsloth-q4_k_m @ unsloth/Qwen3.8-27B-GGUF"), votes=2),
         comment(11, block(model="qwen3.8-27b", thinking="sometimes", colour="blue"), votes=1)],
        models)
    unknown = sync.build_request(issue(2, "Eval request: zai-org/GLM-5.3", block(model="zai-org/GLM-5.3"), votes=1), [], models)
    empty = sync.build_request(issue(3, "Eval request: some model", "no block here"), [], models)

    v = q38["variants"]
    assert [x["id"] for x in v] == ["1-body", "1-c10-1", "1-c10-2", "1-c11"], [x["id"] for x in v]
    assert v[0]["thinking"] == "on" and v[0]["quantKnown"] and v[0]["modelKnown"] and not v[0]["errors"]
    assert v[1]["quant"] == "any" and v[1]["quantKnown"] and v[1]["harness"] == "any" and v[1]["thinking"] == "on:xhigh"
    assert not v[2]["quantKnown"] and not v[2]["errors"]
    assert len(v[3]["errors"]) == 2, v[3]["errors"]
    assert q38["votes"] == 4 + 2 + 1, q38["votes"]  # comment 10's two blocks count its votes once
    assert unknown["model"] == "zai-org/GLM-5.3" and not unknown["modelKnown"] and not unknown["variants"][0]["errors"]
    assert empty["variants"] == [] and empty["model"] == "some model" and empty["votes"] == 0
    print(json.dumps(q38, indent=2)[:600])
    print("ok")


if __name__ == "__main__":
    main()
