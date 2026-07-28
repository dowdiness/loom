#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
checker="$repo_root/scripts/markdown-ir-perf-guard.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

write_output() {
  local path="$1" realistic_direct="$2" realistic_ir="$3"
  local scaled_direct="$4" scaled_ir="$5"
  cat > "$path" <<EOF
[bench] ("markdown: realistic doc - lowering SyntaxNode -> Block") ok
  $realistic_direct
[bench] ("markdown: realistic doc - lowering SyntaxNode -> MarkdownIR -> Block") ok
  $realistic_ir
[bench] ("markdown: 50x doc - lowering SyntaxNode -> Block") ok
  $scaled_direct
[bench] ("markdown: 50x doc - lowering SyntaxNode -> MarkdownIR -> Block") ok
  $scaled_ir
EOF
}

run_case() {
  local expected_exit="$1"
  shift
  set +e
  bash "$checker" "$@" > "$fixture/stdout" 2> "$fixture/stderr"
  actual=$?
  set -e
  if [[ "$actual" -ne "$expected_exit" ]]; then
    printf 'SELFTEST FAIL: expected exit %s, got %s\n' "$expected_exit" "$actual"
    cat "$fixture/stdout" "$fixture/stderr"
    exit 1
  fi
}

assert_stdout_contains() {
  local needle="$1"
  if [[ "$(cat "$fixture/stdout")" != *"$needle"* ]]; then
    printf 'SELFTEST FAIL: stdout missing %s\n' "$needle"
    cat "$fixture/stdout"
    exit 1
  fi
}

assert_stderr_contains() {
  local needle="$1"
  if [[ "$(cat "$fixture/stderr")" != *"$needle"* ]]; then
    printf 'SELFTEST FAIL: stderr missing %s\n' "$needle"
    cat "$fixture/stderr"
    exit 1
  fi
}

for trial in 1 2 3; do
  write_output "$fixture/base-$trial" "100 us" "100 us" "1 ms" "1 ms"
  write_output "$fixture/green-$trial" "100 us" "130 us" "1 ms" "1.3 ms"
  write_output "$fixture/regression-$trial" "100 us" "200 us" "1 ms" "2 ms"
  write_output "$fixture/realistic-regression-$trial" \
    "100 us" "200 us" "1 ms" "1.3 ms"
  write_output "$fixture/scaled-regression-$trial" \
    "100 us" "130 us" "1 ms" "2 ms"
  write_output "$fixture/drift-$trial" "200 us" "200 us" "2 ms" "2 ms"
  write_output "$fixture/control-noise-$trial" "50 us" "100 us" "0.5 ms" "1 ms"
done

run_case 0 \
  "$fixture/base-1" "$fixture/green-1" \
  "$fixture/base-2" "$fixture/green-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stdout_contains 'PASS: no persistent MarkdownIR lowering regression'

run_case 1 \
  "$fixture/base-1" "$fixture/regression-1" \
  "$fixture/base-2" "$fixture/regression-2" \
  "$fixture/base-3" "$fixture/regression-3"
assert_stdout_contains 'FAIL: persistent MarkdownIR lowering regression'
assert_stdout_contains 'realistic'
assert_stdout_contains '50x'

run_case 1 \
  "$fixture/base-1" "$fixture/realistic-regression-1" \
  "$fixture/base-2" "$fixture/realistic-regression-2" \
  "$fixture/base-3" "$fixture/realistic-regression-3"
assert_stdout_contains 'FAIL: persistent MarkdownIR lowering regression [realistic]'

run_case 1 \
  "$fixture/base-1" "$fixture/scaled-regression-1" \
  "$fixture/base-2" "$fixture/scaled-regression-2" \
  "$fixture/base-3" "$fixture/scaled-regression-3"
assert_stdout_contains 'FAIL: persistent MarkdownIR lowering regression [50x]'

# Two bad trials and one healthy trial are noise, not a persistent regression.
run_case 0 \
  "$fixture/base-1" "$fixture/regression-1" \
  "$fixture/base-2" "$fixture/regression-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stdout_contains 'PASS: no persistent MarkdownIR lowering regression'

# A persistent 2x shared-path slowdown must trip the independent hard ceiling,
# even though the within-run MarkdownIR/direct ratio stays flat.
run_case 1 \
  "$fixture/base-1" "$fixture/drift-1" \
  "$fixture/base-2" "$fixture/drift-2" \
  "$fixture/base-3" "$fixture/drift-3"
assert_stdout_contains 'FAIL: persistent MarkdownIR lowering regression'
assert_stdout_contains 'hard ceiling'

# The ceiling is inclusive: 2x is exactly +100% and fails above, while a
# configured +100.1% ceiling permits the same measurements.
MARKDOWN_IR_PERF_HARD_CEILING_PERCENT=100.1 run_case 0 \
  "$fixture/base-1" "$fixture/drift-1" \
  "$fixture/base-2" "$fixture/drift-2" \
  "$fixture/base-3" "$fixture/drift-3"
assert_stdout_contains 'PASS: no persistent MarkdownIR lowering regression'
assert_stdout_contains 'hard ceiling: >=+100.1% raw'

# A noisy direct control alone cannot fail the guard: absolute IR regression is
# also required in every trial.
run_case 0 \
  "$fixture/base-1" "$fixture/control-noise-1" \
  "$fixture/base-2" "$fixture/control-noise-2" \
  "$fixture/base-3" "$fixture/control-noise-3"
assert_stdout_contains 'PASS: no persistent MarkdownIR lowering regression'

cp "$fixture/base-1" "$fixture/missing"
sed -i '/50x doc - lowering SyntaxNode -> MarkdownIR/,+1d' "$fixture/missing"
run_case 2 \
  "$fixture/base-1" "$fixture/missing" \
  "$fixture/base-2" "$fixture/green-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stderr_contains 'missing benchmark'

cp "$fixture/base-1" "$fixture/unknown-unit"
sed -i 's/100 us/100 bananas/' "$fixture/unknown-unit"
run_case 2 \
  "$fixture/base-1" "$fixture/unknown-unit" \
  "$fixture/base-2" "$fixture/green-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stderr_contains 'unrecognised unit'

for invalid_hard_ceiling in not-a-number 0; do
  MARKDOWN_IR_PERF_HARD_CEILING_PERCENT="$invalid_hard_ceiling" run_case 2 \
    "$fixture/base-1" "$fixture/green-1" \
    "$fixture/base-2" "$fixture/green-2" \
    "$fixture/base-3" "$fixture/green-3"
  assert_stderr_contains 'MARKDOWN_IR_PERF_HARD_CEILING_PERCENT must be a positive number'
done

run_case 2 "$fixture/base-1" "$fixture/green-1"
assert_stderr_contains 'exactly 3 base/head trial pairs'
assert_stderr_contains 'MARKDOWN_IR_PERF_HARD_CEILING_PERCENT=100'

printf 'SELFTEST PASS\n'
