#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf 'Usage: markdown-source-bound-api-kind.sh REPOSITORY\n' >&2
  exit 2
fi

readonly repository="$1"
readonly current_document_marker='^[[:space:]]*pub fn MarkdownDocument::semantic_read[[:space:]]*\('
readonly current_attachment_marker='^[[:space:]]*pub fn MarkdownSemanticAttachment::source_document[[:space:]]*\('
readonly legacy_marker='^[[:space:]]*pub fn MarkdownSemanticAttachment::document[[:space:]]*\('
if ! git -C "$repository" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'source-bound API capability probe: not a Git worktree: %s\n' \
    "$repository" >&2
  exit 2
fi

has_current_document=false
if git -C "$repository" grep -q -E -- "$current_document_marker" -- '*.mbt'; then
  has_current_document=true
fi
has_current_attachment=false
if git -C "$repository" grep -q -E -- "$current_attachment_marker" -- '*.mbt'; then
  has_current_attachment=true
fi
has_legacy=false
if git -C "$repository" grep -q -E -- "$legacy_marker" -- '*.mbt'; then
  has_legacy=true
fi
if [[ "$has_current_document" == true && "$has_current_attachment" == true ]]; then
  printf 'current\n'
elif [[ "$has_current_document" == false &&
  "$has_current_attachment" == false &&
  "$has_legacy" == true ]]; then
  printf 'legacy\n'
else
  printf 'source-bound API capability probe: unknown revision in %s\n' \
    "$repository" >&2
  exit 2
fi
