#!/usr/bin/env bash
# Compare three alternating base/head Markdown benchmark trials.
#
# The guard is intentionally coarse and low-noise. Its usual signal requires
# both the MarkdownIR wall time and its within-run ratio to the direct Block
# control to regress beyond the configured threshold. An independent raw-time
# hard ceiling catches large shared-path slowdowns even when that ratio is flat.
# A case blocks a PR only when a bad signal persists in all three trials. The
# weekly detector keeps the more sensitive absolute-baseline check.

set -euo pipefail

readonly trial_pairs=3
readonly threshold_percent="${MARKDOWN_IR_PERF_THRESHOLD_PERCENT:-50}"
readonly hard_ceiling_percent="${MARKDOWN_IR_PERF_HARD_CEILING_PERCENT:-100}"
readonly realistic_direct='markdown: realistic doc - lowering SyntaxNode -> Block'
readonly realistic_ir='markdown: realistic doc - lowering SyntaxNode -> MarkdownIR -> Block'
readonly scaled_direct='markdown: 50x doc - lowering SyntaxNode -> Block'
readonly scaled_ir='markdown: 50x doc - lowering SyntaxNode -> MarkdownIR -> Block'

usage() {
  cat >&2 <<'EOF'
Usage: markdown-ir-perf-guard.sh BASE_1 HEAD_1 BASE_2 HEAD_2 BASE_3 HEAD_3

Each argument is raw `moon bench` output containing the four Markdown lowering
benchmarks. Exit 0 means no persistent regression, 1 means regression, and 2
means the comparison input or verifier is invalid.

MARKDOWN_IR_PERF_HARD_CEILING_PERCENT=100 is the default inclusive raw-slowdown
ceiling. Override it with a positive percentage when runner policy requires it.
EOF
}

infra_fail() {
  printf 'PERF GUARD ERROR: %s\n' "$*" >&2
  exit 2
}

if [[ "$#" -ne $((trial_pairs * 2)) ]]; then
  usage
  infra_fail "expected exactly $trial_pairs base/head trial pairs"
fi
if [[ ! "$threshold_percent" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  infra_fail "MARKDOWN_IR_PERF_THRESHOLD_PERCENT must be a non-negative number"
fi
if [[ ! "$hard_ceiling_percent" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
  ! awk -v value="$hard_ceiling_percent" 'BEGIN { exit !(value > 0) }'; then
  infra_fail "MARKDOWN_IR_PERF_HARD_CEILING_PERCENT must be a positive number"
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

parse_bench_output() {
  local input="$1" label="$2" output="$3"
  [[ -f "$input" ]] || {
    printf '%s: benchmark output file not found: %s\n' "$label" "$input" >&2
    return 1
  }
  awk \
    -v label="$label" \
    -v realistic_direct="$realistic_direct" \
    -v realistic_ir="$realistic_ir" \
    -v scaled_direct="$scaled_direct" \
    -v scaled_ir="$scaled_ir" '
    BEGIN {
      wanted[realistic_direct] = 1
      wanted[realistic_ir] = 1
      wanted[scaled_direct] = 1
      wanted[scaled_ir] = 1
    }
    /\) ok$/ {
      name = $0
      sub(/.*\("/, "", name)
      sub(/"\).*/, "", name)
      pending = name
      next
    }
    pending != "" && /^[[:space:]]+[0-9]/ {
      value = $1
      unit = $2
      name = pending
      pending = ""
      if (!(name in wanted)) next
      if (unit == "ns") mult = 1
      else if (unit == "us" || unit == "µs" || unit == "μs") mult = 1000
      else if (unit == "ms") mult = 1000000
      else if (unit == "s") mult = 1000000000
      else {
        printf "%s: unrecognised unit for %s: %s\n", label, name, unit > "/dev/stderr"
        bad = 1
        next
      }
      if (value !~ /^[0-9]+([.][0-9]+)?$/) {
        printf "%s: malformed measurement for %s: %s\n", label, name, value > "/dev/stderr"
        bad = 1
        next
      }
      if (name in seen) {
        printf "%s: duplicate benchmark: %s\n", label, name > "/dev/stderr"
        bad = 1
        next
      }
      seen[name] = 1
      printf "%s\t%.2f\n", name, value * mult
    }
    END {
      for (name in wanted) {
        if (!(name in seen)) {
          printf "%s: missing benchmark: %s\n", label, name > "/dev/stderr"
          bad = 1
        }
      }
      exit bad
    }
  ' "$input" > "$output"
}

for trial in 1 2 3; do
  base_arg=$((trial * 2 - 1))
  head_arg=$((trial * 2))
  base_file="${!base_arg}"
  head_file="${!head_arg}"
  parse_bench_output "$base_file" "base trial $trial" "$work_dir/base-$trial.tsv" || exit 2
  parse_bench_output "$head_file" "head trial $trial" "$work_dir/head-$trial.tsv" || exit 2
done

read_value() {
  local input="$1" benchmark="$2"
  awk -F '\t' -v benchmark="$benchmark" '$1 == benchmark { print $2 }' "$input"
}

bad_realistic=0
bad_scaled=0
case_bad=0

printf 'MarkdownIR PR performance guard (threshold: +%s%% raw+normalized; hard ceiling: >=+%s%% raw; persistence: %s/%s)\n' \
  "$threshold_percent" "$hard_ceiling_percent" "$trial_pairs" "$trial_pairs"

check_case() {
  local trial="$1" label="$2" direct_name="$3" ir_name="$4"
  local base_tsv="$work_dir/base-$trial.tsv" head_tsv="$work_dir/head-$trial.tsv"
  local base_direct_value base_ir_value head_direct_value head_ir_value metrics
  base_direct_value=$(read_value "$base_tsv" "$direct_name")
  base_ir_value=$(read_value "$base_tsv" "$ir_name")
  head_direct_value=$(read_value "$head_tsv" "$direct_name")
  head_ir_value=$(read_value "$head_tsv" "$ir_name")

  metrics=$(awk \
    -v bd="$base_direct_value" -v bi="$base_ir_value" \
    -v hd="$head_direct_value" -v hi="$head_ir_value" \
    -v threshold="$threshold_percent" \
    -v hard_ceiling="$hard_ceiling_percent" '
      BEGIN {
        if (bd <= 0 || bi <= 0 || hd <= 0 || hi <= 0) exit 2
        raw = (hi / bi - 1) * 100
        normalized = ((hi / hd) / (bi / bd) - 1) * 100
        relative_bad = raw > threshold && normalized > threshold
        hard_bad = raw >= hard_ceiling
        bad = relative_bad || hard_bad
        printf "%.1f\t%.1f\t%d\t%d", raw, normalized, bad, hard_bad
      }
    ') || \
    infra_fail "non-positive or invalid measurement in trial $trial ($label)"

  local raw_percent normalized_percent bad hard_bad status
  IFS=$'\t' read -r raw_percent normalized_percent bad hard_bad <<< "$metrics"
  status=ok
  if [[ "$hard_bad" == 1 ]]; then
    status='BAD (hard ceiling)'
  elif [[ "$bad" == 1 ]]; then
    status=BAD
  fi
  printf '  trial %s %-9s IR base/head %s/%s ns (%+.1f%%); normalized %+.1f%%; %s\n' \
    "$trial" "$label" "$base_ir_value" "$head_ir_value" \
    "$raw_percent" "$normalized_percent" "$status"
  case_bad="$bad"
}

for trial in 1 2 3; do
  check_case "$trial" realistic "$realistic_direct" "$realistic_ir"
  bad_realistic=$((bad_realistic + case_bad))
  check_case "$trial" 50x "$scaled_direct" "$scaled_ir"
  bad_scaled=$((bad_scaled + case_bad))
done

if [[ "$bad_realistic" -eq "$trial_pairs" || "$bad_scaled" -eq "$trial_pairs" ]]; then
  printf 'FAIL: persistent MarkdownIR lowering regression'
  [[ "$bad_realistic" -eq "$trial_pairs" ]] && printf ' [realistic]'
  [[ "$bad_scaled" -eq "$trial_pairs" ]] && printf ' [50x]'
  printf '\n'
  exit 1
fi

printf 'PASS: no persistent MarkdownIR lowering regression'
if [[ "$bad_realistic" -gt 0 || "$bad_scaled" -gt 0 ]]; then
  printf ' (non-persistent observations: realistic=%s/%s, 50x=%s/%s)' \
    "$bad_realistic" "$trial_pairs" "$bad_scaled" "$trial_pairs"
fi
printf '\n'
