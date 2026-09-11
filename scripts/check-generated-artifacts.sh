#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "usage: scripts/check-generated-artifacts.sh <repo-relative-path>..." >&2
  exit 2
fi

repo_root=$(git rev-parse --show-toplevel)
git -C "$repo_root" ls-files --error-unmatch -- "$@" >/dev/null

status=$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all -- "$@")
if [[ -n "$status" ]]; then
  printf 'generated artifact set is not clean:\n%s\n' "$status" >&2
  exit 1
fi
