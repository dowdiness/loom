#!/usr/bin/env bash
set -euo pipefail

classifier=$(cd "$(dirname "$0")" && pwd)/markdown-source-bound-api-kind.sh
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

init_repo() {
  local repository="$1"
  mkdir -p "$repository"
  git -C "$repository" init -q
  git -C "$repository" config user.email fixture@example.test
  git -C "$repository" config user.name fixture
}

commit_fixture() {
  local repository="$1"
  git -C "$repository" add .
  git -C "$repository" commit -qm fixture
}

assert_probe() {
  local repository="$1" expected="$2" actual
  actual=$(bash "$classifier" "$repository")
  if [[ "$actual" != "$expected" ]]; then
    printf 'SELFTEST FAIL: expected %s, got %s\n' "$expected" "$actual"
    exit 1
  fi
}

current_repository="$fixture/current"
init_repo "$current_repository"
mkdir -p "$current_repository/examples/markdown"
printf 'pub fn MarkdownDocument::semantic_read(\n' \
  > "$current_repository/examples/markdown/renamed_document.mbt"
commit_fixture "$current_repository"
assert_probe "$current_repository" current

coexist_repository="$fixture/coexist"
init_repo "$coexist_repository"
mkdir -p "$coexist_repository/examples/markdown"
printf '%s\n%s\n' \
  'pub fn MarkdownDocument::semantic_read(' \
  'pub fn MarkdownSemanticAttachment::document(' \
  > "$coexist_repository/examples/markdown/markdown_document_compatibility.mbt"
commit_fixture "$coexist_repository"
assert_probe "$coexist_repository" current

legacy_repository="$fixture/legacy"
init_repo "$legacy_repository"
mkdir -p "$legacy_repository/examples/markdown"
printf 'pub fn MarkdownSemanticAttachment::document(\n' \
  > "$legacy_repository/examples/markdown/markdown_semantic_attachment.mbt"
commit_fixture "$legacy_repository"
assert_probe "$legacy_repository" legacy

unknown_repository="$fixture/unknown"
init_repo "$unknown_repository"
mkdir -p "$unknown_repository/examples/markdown"
printf 'pub fn parse_cst(\n' > "$unknown_repository/examples/markdown/parser.mbt"
commit_fixture "$unknown_repository"
if bash "$classifier" "$unknown_repository" > "$fixture/unknown.stdout" \
  2> "$fixture/unknown.stderr"; then
  printf 'SELFTEST FAIL: unknown capability was accepted\n'
  exit 1
fi
if [[ "$(cat "$fixture/unknown.stderr")" != *'unknown revision'* ]]; then
  printf 'SELFTEST FAIL: unknown capability diagnostic missing\n'
  cat "$fixture/unknown.stderr"
  exit 1
fi

printf 'SELFTEST PASS\n'
