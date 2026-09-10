#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:?usage: secret_scan.sh DIRECTORY}"
[[ -d "$TARGET" ]] || { echo "directory not found: $TARGET" >&2; exit 2; }
if find "$TARGET" -type f \( -name '.env' -o -name '*.pem' -o -name '*.key' \) -print -quit | grep -q .; then
  echo "secret-like file present in bundle" >&2
  exit 1
fi
if rg -n --hidden --glob '!*.png' --glob '!*.jpg' --glob '!*.gif' \
  '(OPENROUTER_API_KEY|RUNPOD_API_KEY|HETZNER.*TOKEN|GITHUB_TOKEN|Authorization: Bearer|BEGIN (RSA|OPENSSH|EC|PRIVATE) KEY|sk-[A-Za-z0-9_-]{20,})' "$TARGET"; then
  echo "potential secret found in bundle" >&2
  exit 1
fi
echo "secret scan passed: $TARGET"
