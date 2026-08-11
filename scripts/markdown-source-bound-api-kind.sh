#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'Usage: markdown-source-bound-api-kind.sh REPOSITORY\n' >&2
  exit 2
fi

readonly repository="$1"
readonly current_marker='^[[:space:]]*pub fn MarkdownDocument::semantic_read[[:space:]]*\('
readonly legacy_marker='^[[:space:]]*pub fn MarkdownSemanticAttachment::document[[:space:]]*\('
if ! git -C "$repository" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'source-bound API capability probe: not a Git worktree: %s\n' \
    "$repository" >&2
  exit 2
fi

if git -C "$repository" grep -q -E -- "$current_marker" -- '*.mbt'; then
  printf 'current\n'
elif git -C "$repository" grep -q -E -- "$legacy_marker" -- '*.mbt'; then
  printf 'legacy\n'
else
  printf 'source-bound API capability probe: unknown revision in %s\n' \
    "$repository" >&2
  exit 2
fi
