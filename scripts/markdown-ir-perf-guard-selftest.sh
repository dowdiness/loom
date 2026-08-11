#!/usr/bin/env bash
set -euo pipefail

# Preserve detailed assertions below; production CI uses the compact default.
export MARKDOWN_PERF_GUARD_VERBOSE=1

repo_root=$(cd "$(dirname "$0")/.." && pwd)
checker="$repo_root/scripts/markdown-ir-perf-guard.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

readonly delimiter_64_full='markdown delimiter-heavy 64x full parse'
readonly plain_64_full='markdown plain-control 64x full parse'
readonly delimiter_64_incremental='markdown delimiter-heavy 64x incremental edit+restore'
readonly plain_64_incremental='markdown plain-control 64x incremental edit+restore'
readonly delimiter_256_full='markdown delimiter-heavy 256x full parse'
readonly plain_256_full='markdown plain-control 256x full parse'
readonly delimiter_256_incremental='markdown delimiter-heavy 256x incremental edit+restore'
readonly plain_256_incremental='markdown plain-control 256x incremental edit+restore'
readonly source_bound_control='perf source-bound benchmark control'
readonly source_bound_parse='perf source-bound parse_document 100 paragraphs'
readonly source_bound_semantic='perf source-bound semantic_read 100 paragraphs'
readonly source_bound_block='perf source-bound Block adapter 100 paragraphs'
readonly source_bound_mdast='perf source-bound mdast adapter 100 paragraphs'
readonly source_bound_preserve='perf source-bound preserve rewrite 100 paragraphs'
readonly source_bound_local='perf source-bound local rewrite selection'
readonly source_bound_ir_only='perf source-bound IR-only target through read'
readonly source_bound_attachment='perf source-bound attachment source_document'

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
[bench] ("$delimiter_64_full") ok
  100 us
[bench] ("$plain_64_full") ok
  100 us
[bench] ("$delimiter_64_incremental") ok
  200 us
[bench] ("$plain_64_incremental") ok
  200 us
[bench] ("$delimiter_256_full") ok
  1 ms
[bench] ("$plain_256_full") ok
  1 ms
[bench] ("$delimiter_256_incremental") ok
  2 ms
[bench] ("$plain_256_incremental") ok
  2 ms
[bench] ("$source_bound_control") ok
  100 us
[bench] ("$source_bound_parse") ok
  100 us
[bench] ("$source_bound_semantic") ok
  100 us
[bench] ("$source_bound_block") ok
  100 us
[bench] ("$source_bound_mdast") ok
  100 us
[bench] ("$source_bound_preserve") ok
  100 us
[bench] ("$source_bound_local") ok
  100 us
[bench] ("$source_bound_ir_only") ok
  100 us
[bench] ("$source_bound_attachment") ok
  100 us
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
  write_output "$fixture/direct-regression-$trial" \
    "160 us" "100 us" "1.6 ms" "1 ms"
  write_output "$fixture/drift-$trial" "200 us" "200 us" "2 ms" "2 ms"
  write_output "$fixture/control-noise-$trial" "50 us" "100 us" "0.5 ms" "1 ms"
  cp "$fixture/base-$trial" "$fixture/source-bound-regression-$trial"
  sed -i "/$source_bound_block/{n;s/100 us/500 us/;}" \
    "$fixture/source-bound-regression-$trial"
  cp "$fixture/base-$trial" "$fixture/delimiter-calibration-$trial"
  sed -i "/$delimiter_64_full/{n;s/100 us/160 us/;}" \
    "$fixture/delimiter-calibration-$trial"
  cp "$fixture/base-$trial" "$fixture/delimiter-subject-at-threshold-$trial"
  sed -i "/$delimiter_64_full/{n;s/100 us/150 us/;}" \
    "$fixture/delimiter-subject-at-threshold-$trial"
  cp "$fixture/base-$trial" "$fixture/delimiter-control-regression-$trial"
  sed -i "/$plain_64_incremental/{n;s/200 us/320 us/;}" \
    "$fixture/delimiter-control-regression-$trial"
  cp "$fixture/base-$trial" "$fixture/delimiter-control-at-threshold-$trial"
  sed -i "/$plain_64_incremental/{n;s/200 us/300 us/;}" \
    "$fixture/delimiter-control-at-threshold-$trial"
  cp "$fixture/base-$trial" "$fixture/delimiter-hard-ceiling-$trial"
  sed -i "/$delimiter_256_full/{n;s/1 ms/2 ms/;}" \
    "$fixture/delimiter-hard-ceiling-$trial"
  sed -i "/$plain_256_full/{n;s/1 ms/2 ms/;}" \
    "$fixture/delimiter-hard-ceiling-$trial"
done

run_case 0 \
  "$fixture/base-1" "$fixture/green-1" \
  "$fixture/base-2" "$fixture/green-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stdout_contains 'PASS: no persistent Markdown lowering regression'
assert_stdout_contains 'Delimiter performance gate (subject threshold: +50% raw+normalized; hard ceiling: >=+100% raw; plain-control threshold: +50% raw'

run_case 1 \
  "$fixture/base-1" "$fixture/source-bound-regression-1" \
  "$fixture/base-2" "$fixture/source-bound-regression-2" \
  "$fixture/base-3" "$fixture/source-bound-regression-3"
assert_stdout_contains 'FAIL: persistent source-bound regression [Block adapter]'

# Explicit A/A calibration keeps delimiter rows required and records their
# deltas without making a delimiter performance verdict.
MARKDOWN_DELIMITER_PERF_CALIBRATION=1 run_case 0 \
  "$fixture/base-1" "$fixture/delimiter-calibration-1" \
  "$fixture/base-2" "$fixture/delimiter-calibration-2" \
  "$fixture/base-3" "$fixture/delimiter-calibration-3"
assert_stdout_contains 'CALIBRATION: delimiter verdict disabled explicitly'
assert_stdout_contains 'delimiter 64x full parse'
assert_stdout_contains 'subject 100000.00/160000.00 ns (+60.0%); normalized +60.0%; CALIBRATION'

MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT=50 \
MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT=100 \
MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT=50 \
run_case 0 \
  "$fixture/base-1" "$fixture/base-1" \
  "$fixture/base-2" "$fixture/base-2" \
  "$fixture/base-3" "$fixture/base-3"
assert_stdout_contains 'Delimiter performance gate (subject threshold: +50% raw+normalized'
assert_stdout_contains 'delimiter 256x incremental edit+restore'

MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT=50 \
MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT=100 \
MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT=50 \
MARKDOWN_DELIMITER_PERF_CALIBRATION=0 \
run_case 1 \
  "$fixture/base-1" "$fixture/delimiter-calibration-1" \
  "$fixture/base-2" "$fixture/delimiter-calibration-2" \
  "$fixture/base-3" "$fixture/delimiter-calibration-3"
assert_stdout_contains 'FAIL: persistent delimiter-heavy regression [64x full parse]'

MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT=50 \
MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT=100 \
MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT=50 \
run_case 0 \
  "$fixture/base-1" "$fixture/delimiter-calibration-1" \
  "$fixture/base-2" "$fixture/delimiter-calibration-2" \
  "$fixture/base-3" "$fixture/base-3"
assert_stdout_contains 'PASS: no persistent Markdown lowering regression'
assert_stdout_contains 'delimiter 64x full parse=2/3'

# Relative subject and plain-control thresholds are strict: an exact +50%
# change remains healthy, while the +60% fixtures below are actionable.
MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT=50 \
MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT=100 \
MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT=50 \
run_case 0 \
  "$fixture/base-1" "$fixture/delimiter-subject-at-threshold-1" \
  "$fixture/base-2" "$fixture/delimiter-subject-at-threshold-2" \
  "$fixture/base-3" "$fixture/delimiter-subject-at-threshold-3"
assert_stdout_contains 'subject 100000.00/150000.00 ns (+50.0%); normalized +50.0%; ok'

MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT=50 \
MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT=100 \
MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT=50 \
run_case 0 \
  "$fixture/base-1" "$fixture/delimiter-control-at-threshold-1" \
  "$fixture/base-2" "$fixture/delimiter-control-at-threshold-2" \
  "$fixture/base-3" "$fixture/delimiter-control-at-threshold-3"
assert_stdout_contains 'plain-control base/head 200000.00/300000.00 ns (+50.0%)'

# A shared-path 2x slowdown keeps the subject/control ratio flat, so only the
# inclusive delimiter hard ceiling should classify the subject as bad.
MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT=50 \
MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT=100 \
MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT=100.1 \
run_case 1 \
  "$fixture/base-1" "$fixture/delimiter-hard-ceiling-1" \
  "$fixture/base-2" "$fixture/delimiter-hard-ceiling-2" \
  "$fixture/base-3" "$fixture/delimiter-hard-ceiling-3"
assert_stdout_contains 'BAD (hard ceiling)'
assert_stdout_contains 'FAIL: persistent delimiter-heavy regression [256x full parse]'

# A regressed plain control is independently actionable and cannot make the
# normalized delimiter signal look healthier.
MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT=50 \
MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT=100 \
MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT=50 \
run_case 1 \
  "$fixture/base-1" "$fixture/delimiter-control-regression-1" \
  "$fixture/base-2" "$fixture/delimiter-control-regression-2" \
  "$fixture/base-3" "$fixture/delimiter-control-regression-3"
assert_stdout_contains 'FAIL: persistent delimiter plain-control regression [64x incremental edit+restore]'

MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT=50 \
MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT=100 \
MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT=50 \
MARKDOWN_DELIMITER_PERF_CALIBRATION=1 \
run_case 0 \
  "$fixture/base-1" "$fixture/delimiter-calibration-1" \
  "$fixture/base-2" "$fixture/delimiter-calibration-2" \
  "$fixture/base-3" "$fixture/delimiter-calibration-3"
assert_stdout_contains 'CALIBRATION: delimiter verdict disabled explicitly'
assert_stdout_contains 'subject 100000.00/160000.00 ns (+60.0%); normalized +60.0%; CALIBRATION'

# Explicit delimiter calibration must not weaken the established legacy gate.
MARKDOWN_DELIMITER_PERF_CALIBRATION=1 \
run_case 1 \
  "$fixture/base-1" "$fixture/regression-1" \
  "$fixture/base-2" "$fixture/regression-2" \
  "$fixture/base-3" "$fixture/regression-3"
assert_stdout_contains 'FAIL: persistent MarkdownIR lowering regression'

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

# A persistent direct-only slowdown is independently actionable. Otherwise it
# improves the normalized MarkdownIR ratio and can hide the regressed control.
run_case 1 \
  "$fixture/base-1" "$fixture/direct-regression-1" \
  "$fixture/base-2" "$fixture/direct-regression-2" \
  "$fixture/base-3" "$fixture/direct-regression-3"
assert_stdout_contains 'FAIL: persistent direct Block lowering regression'
assert_stdout_contains 'realistic'
assert_stdout_contains '50x'

# Direct regressions must also persist in all three trials.
run_case 0 \
  "$fixture/base-1" "$fixture/direct-regression-1" \
  "$fixture/base-2" "$fixture/direct-regression-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stdout_contains 'PASS: no persistent Markdown lowering regression'
assert_stdout_contains 'direct realistic=2/3'
assert_stdout_contains 'direct 50x=2/3'

# Two bad trials and one healthy trial are noise, not a persistent regression.
run_case 0 \
  "$fixture/base-1" "$fixture/regression-1" \
  "$fixture/base-2" "$fixture/regression-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stdout_contains 'PASS: no persistent Markdown lowering regression'
assert_stdout_contains 'IR realistic=2/3'
assert_stdout_contains 'IR 50x=2/3'

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
MARKDOWN_IR_PERF_HARD_CEILING_PERCENT=100.1 \
MARKDOWN_DIRECT_PERF_THRESHOLD_PERCENT=100.1 run_case 0 \
  "$fixture/base-1" "$fixture/drift-1" \
  "$fixture/base-2" "$fixture/drift-2" \
  "$fixture/base-3" "$fixture/drift-3"
assert_stdout_contains 'PASS: no persistent Markdown lowering regression'
assert_stdout_contains 'hard ceiling: >=+100.1% raw'

# A noisy direct control alone cannot fail the guard: absolute IR regression is
# also required in every trial.
run_case 0 \
  "$fixture/base-1" "$fixture/control-noise-1" \
  "$fixture/base-2" "$fixture/control-noise-2" \
  "$fixture/base-3" "$fixture/control-noise-3"
assert_stdout_contains 'PASS: no persistent Markdown lowering regression'

cp "$fixture/base-1" "$fixture/missing"
sed -i '/50x doc - lowering SyntaxNode -> MarkdownIR/,+1d' "$fixture/missing"
run_case 2 \
  "$fixture/base-1" "$fixture/missing" \
  "$fixture/base-2" "$fixture/green-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stderr_contains 'missing benchmark'

cp "$fixture/base-1" "$fixture/missing-delimiter"
sed -i "/$delimiter_64_full/,+1d" "$fixture/missing-delimiter"
MARKDOWN_DELIMITER_PERF_CALIBRATION=1 run_case 2 \
  "$fixture/base-1" "$fixture/missing-delimiter" \
  "$fixture/base-2" "$fixture/green-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stderr_contains "missing benchmark: $delimiter_64_full"

cp "$fixture/base-1" "$fixture/duplicate-delimiter"
printf '[bench] ("%s") ok\n  2 ms\n' "$delimiter_256_incremental" \
  >> "$fixture/duplicate-delimiter"
MARKDOWN_DELIMITER_PERF_CALIBRATION=1 run_case 2 \
  "$fixture/base-1" "$fixture/duplicate-delimiter" \
  "$fixture/base-2" "$fixture/green-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stderr_contains "duplicate benchmark: $delimiter_256_incremental"

cp "$fixture/base-1" "$fixture/malformed-delimiter-unit"
sed -i "/$delimiter_64_incremental/{n;s/200 us/200 bananas/;}" \
  "$fixture/malformed-delimiter-unit"
MARKDOWN_DELIMITER_PERF_CALIBRATION=1 run_case 2 \
  "$fixture/base-1" "$fixture/malformed-delimiter-unit" \
  "$fixture/base-2" "$fixture/green-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stderr_contains "unrecognised unit for $delimiter_64_incremental: bananas"

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

MARKDOWN_DIRECT_PERF_THRESHOLD_PERCENT=not-a-number run_case 2 \
  "$fixture/base-1" "$fixture/green-1" \
  "$fixture/base-2" "$fixture/green-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stderr_contains 'MARKDOWN_DIRECT_PERF_THRESHOLD_PERCENT must be a non-negative number'

MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT=not-a-number run_case 2 \
  "$fixture/base-1" "$fixture/green-1" \
  "$fixture/base-2" "$fixture/green-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stderr_contains 'MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT must be a non-negative number'

for invalid_delimiter_hard_ceiling in not-a-number 0; do
  MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT="$invalid_delimiter_hard_ceiling" run_case 2 \
    "$fixture/base-1" "$fixture/green-1" \
    "$fixture/base-2" "$fixture/green-2" \
    "$fixture/base-3" "$fixture/green-3"
  assert_stderr_contains 'MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT must be a positive number'
done

MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT=not-a-number run_case 2 \
  "$fixture/base-1" "$fixture/green-1" \
  "$fixture/base-2" "$fixture/green-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stderr_contains 'MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT must be a non-negative number'

MARKDOWN_DELIMITER_PERF_CALIBRATION=2 run_case 2 \
  "$fixture/base-1" "$fixture/green-1" \
  "$fixture/base-2" "$fixture/green-2" \
  "$fixture/base-3" "$fixture/green-3"
assert_stderr_contains 'MARKDOWN_DELIMITER_PERF_CALIBRATION must be 0 or 1'

run_case 2 "$fixture/base-1" "$fixture/green-1"
assert_stderr_contains 'exactly 3 base/head trial pairs'
assert_stderr_contains 'MARKDOWN_IR_PERF_HARD_CEILING_PERCENT=100'

MARKDOWN_PERF_GUARD_VERBOSE=0 \
MARKDOWN_DELIMITER_PERF_CALIBRATION=1 run_case 0 \
  "$fixture/base-1" "$fixture/delimiter-calibration-1" \
  "$fixture/base-2" "$fixture/delimiter-calibration-2" \
  "$fixture/base-3" "$fixture/delimiter-calibration-3"
if grep -q '^  trial ' "$fixture/stdout"; then
  printf 'SELFTEST FAIL: compact calibration output contains per-trial rows\n'
  cat "$fixture/stdout"
  exit 1
fi
assert_stdout_contains 'Markdown performance: 3 alternating base/head trials; IR +50%; delimiter calibration (non-gating)'
assert_stdout_contains 'CALIBRATION: delimiter verdict disabled; raw/normalized deltas over 3 trials'
assert_stdout_contains 'delimiter 64x full parse raw +60.0..+60.0%; normalized +60.0..+60.0%'

MARKDOWN_PERF_GUARD_VERBOSE=0 run_case 0 \
  "$fixture/base-1" "$fixture/green-1" \
  "$fixture/base-2" "$fixture/green-2" \
  "$fixture/base-3" "$fixture/green-3"
if grep -q '^  trial ' "$fixture/stdout"; then
  printf 'SELFTEST FAIL: compact output contains per-trial rows\n'
  cat "$fixture/stdout"
  exit 1
fi
assert_stdout_contains 'Markdown performance: 3 alternating base/head trials'
assert_stdout_contains 'PASS: no persistent Markdown lowering regression'

printf 'SELFTEST PASS\n'
