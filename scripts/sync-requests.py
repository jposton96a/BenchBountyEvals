#!/usr/bin/env python3
"""Collect eval requests from GitHub issues into published/requests.json.

usage: sync-requests.py [--repo owner/name] [--out PATH]   (MODELS_DIR overrides published/models)

One issue per model, labelled agentbench-request or titled "Eval request: <model>" (GitHub
drops the label from prefilled issue links unless the author can triage). Every ```agentbench-request block in
the issue body or a comment is one requested variant; +1 reactions on the comment (or the
issue, for body blocks) are its votes. This only measures demand: "Up next" is ordered by hand.
Token: GITHUB_TOKEN, else `gh auth token`, else unauthenticated (public repos only).
"""
import argparse
import datetime
import json
import os
import pathlib
import re
import subprocess
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
LABEL = "agentbench-request"
AXES = ("model", "quant", "thinking", "harness", "benchmark")
BLOCK = re.compile(r"^```agentbench-request[ \t]*\n(.*?)^```", re.M | re.S)
TITLE = re.compile(r"^eval request:", re.I)
THINKING = re.compile(r"^(any|off|on(:[a-z]+)?)$")
HF_REPO = re.compile(r"^[\w.-]+/[\w.-]+$")


def token():
    if os.environ.get("GITHUB_TOKEN"):
        return os.environ["GITHUB_TOKEN"]
    try:
        return subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def github(path, auth):
    """GET every page of a list endpoint."""
    items, url = [], f"https://api.github.com/{path}{'&' if '?' in path else '?'}per_page=100"
    while url:
        headers = {"Accept": "application/vnd.github+json", "User-Agent": "agentbench-sync-requests"}
        if auth:
            headers["Authorization"] = f"Bearer {auth}"
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as r:
            items += json.load(r)
            url = next((m.group(1) for m in re.finditer(r'<([^>]+)>; rel="next"', r.headers.get("Link", ""))), None)
    return items


def parse_block(text):
    fields, errors = {}, []
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        key, sep, value = line.partition(":")
        key, value = key.strip().lower(), value.strip()
        if not sep or key not in AXES:
            errors.append(f"unknown line: {line}")
        else:
            fields[key] = value or "any"
    variant = {axis: fields.get(axis, "any") for axis in AXES}
    if variant["model"] == "any":
        errors.append("model is required")
    if not THINKING.match(variant["thinking"]):
        errors.append(f"thinking must be off, on, on:<effort> or any, not {variant['thinking']!r}")
    return variant, errors


def check_known(variant, models):
    model = models.get(variant["model"])
    variant["modelKnown"] = model is not None
    if not model and variant["model"] != "any" and not HF_REPO.match(variant["model"]):
        variant["errors"].append(f"model {variant['model']!r} is neither a model id nor an HF repo")
    quant = variant["quant"]
    variant["quantKnown"] = quant == "any" or bool(model and quant in {q["id"] for q in model["quants"]})


def variants_of(issue, comments, models):
    sources = [(f"{issue['number']}-body", issue)] + [(f"{issue['number']}-c{c['id']}", c) for c in comments]
    out = []
    for vid, src in sources:
        blocks = BLOCK.findall((src.get("body") or "").replace("\r\n", "\n"))
        for i, text in enumerate(blocks):
            variant, errors = parse_block(text)
            variant.update({
                "id": vid if len(blocks) == 1 else f"{vid}-{i + 1}",
                "url": src["html_url"],
                "author": (src.get("user") or {}).get("login"),
                "createdAt": src["created_at"],
                "votes": (src.get("reactions") or {}).get("+1", 0),
                "payments": [],
                "errors": errors,
            })
            check_known(variant, models)
            out.append((src["html_url"], variant))
    return out


def build_request(issue, comments, models):
    found = variants_of(issue, comments, models)
    variants = [v for _, v in found]
    votes_by_source = {url: v["votes"] for url, v in found}
    valid = [v for v in variants if not v["errors"]]
    title_model = re.sub(r"^eval request:\s*", "", issue["title"], flags=re.I).strip()
    model = valid[0]["model"] if valid else title_model
    return {
        "issue": issue["number"],
        "url": issue["html_url"],
        "title": issue["title"],
        "state": issue["state"],
        "model": model,
        "modelKnown": model in models,
        "votes": sum(votes_by_source.values()),
        "variants": variants,
    }


def load_models():
    models_dir = pathlib.Path(os.environ.get("MODELS_DIR", ROOT / "published" / "models"))
    return {p.stem: json.loads(p.read_text()) for p in models_dir.glob("*.json")}


def write_atomic(path, doc):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=os.environ.get("REQUESTS_REPO", "jposton96a/BenchBountyEvals"))
    ap.add_argument("--out", type=pathlib.Path, default=ROOT / "published" / "requests.json")
    args = ap.parse_args()

    auth = token()
    models = load_models()
    issues = [i for i in github(f"repos/{args.repo}/issues?state=all", auth)
              if "pull_request" not in i and (LABEL in {l["name"] for l in i["labels"]} or TITLE.match(i["title"]))]
    requests = [build_request(i, github(f"repos/{args.repo}/issues/{i['number']}/comments", auth) if i["comments"] else [], models)
                for i in issues]
    requests.sort(key=lambda r: (-r["votes"], r["issue"]))
    write_atomic(args.out, {
        "schemaVersion": 1,
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "repo": args.repo,
        "requests": requests,
    })
    print(f"{args.out}: {len(requests)} requests, {sum(len(r['variants']) for r in requests)} variants from {args.repo}")


if __name__ == "__main__":
    main()
