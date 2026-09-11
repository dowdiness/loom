#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
checker="$repo_root/scripts/check-generated-artifacts.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

git -C "$fixture" init -q
git -C "$fixture" config user.email selftest@example.invalid
git -C "$fixture" config user.name selftest
mkdir -p "$fixture/generated"
printf 'one\n' > "$fixture/generated/one.txt"
printf 'two\n' > "$fixture/generated/two.txt"
git -C "$fixture" add generated/one.txt generated/two.txt
git -C "$fixture" commit -qm baseline

run_pass() {
  (cd "$fixture" && bash "$checker" "$@") || {
    printf 'SELFTEST FAIL: expected success for %s\n' "$*" >&2
    exit 1
  }
}

run_fail() {
  local label="$1"
  shift
  if (cd "$fixture" && bash "$checker" "$@") >"$fixture/stdout" 2>"$fixture/stderr"; then
    printf 'SELFTEST FAIL: expected failure for %s\n' "$label" >&2
    exit 1
  fi
}

run_pass generated/one.txt
run_pass generated/one.txt generated/two.txt

printf 'changed\n' > "$fixture/generated/one.txt"
run_fail modified generated/one.txt
git -C "$fixture" restore generated/one.txt

rm "$fixture/generated/one.txt"
run_fail missing generated/one.txt
git -C "$fixture" restore generated/one.txt

git -C "$fixture" rm --cached -q generated/one.txt
run_fail deleted-and-recreated generated/one.txt
git -C "$fixture" reset -q HEAD -- generated/one.txt

printf 'changed\n' > "$fixture/generated/two.txt"
run_fail multi-path generated/one.txt generated/two.txt
git -C "$fixture" restore generated/two.txt

run_pass generated/one.txt generated/two.txt
echo "generated artifact self-tests passed"
