#!/usr/bin/env bash
# Compare three alternating base/head Markdown benchmark trials.
#
# The guard is intentionally coarse and low-noise. Its usual signal requires
# both the MarkdownIR wall time and its within-run ratio to the direct Block
# control to regress beyond the configured threshold. An independent raw-time
# hard ceiling catches large shared-path slowdowns even when that ratio is flat.
# Direct Block lowering has its own raw-time threshold so a slow control cannot
# make the normalized MarkdownIR signal look healthier. A case blocks a PR only
# when a bad signal persists in all three trials. The weekly detector keeps the
# more sensitive absolute-baseline check.

set -euo pipefail

readonly trial_pairs=3
readonly threshold_percent="${MARKDOWN_IR_PERF_THRESHOLD_PERCENT:-50}"
readonly hard_ceiling_percent="${MARKDOWN_IR_PERF_HARD_CEILING_PERCENT:-100}"
readonly direct_threshold_percent="${MARKDOWN_DIRECT_PERF_THRESHOLD_PERCENT:-50}"
readonly delimiter_threshold_percent="${MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT:-}"
readonly delimiter_hard_ceiling_percent="${MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT:-}"
readonly delimiter_control_threshold_percent="${MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT:-}"
readonly delimiter_calibration="${MARKDOWN_DELIMITER_PERF_CALIBRATION:-0}"
readonly realistic_direct='markdown: realistic doc - lowering SyntaxNode -> Block'
readonly realistic_ir='markdown: realistic doc - lowering SyntaxNode -> MarkdownIR -> Block'
readonly scaled_direct='markdown: 50x doc - lowering SyntaxNode -> Block'
readonly scaled_ir='markdown: 50x doc - lowering SyntaxNode -> MarkdownIR -> Block'
readonly delimiter_64_full='markdown delimiter-heavy 64x full parse'
readonly plain_64_full='markdown plain-control 64x full parse'
readonly delimiter_64_incremental='markdown delimiter-heavy 64x incremental edit+restore'
readonly plain_64_incremental='markdown plain-control 64x incremental edit+restore'
readonly delimiter_256_full='markdown delimiter-heavy 256x full parse'
readonly plain_256_full='markdown plain-control 256x full parse'
readonly delimiter_256_incremental='markdown delimiter-heavy 256x incremental edit+restore'
readonly plain_256_incremental='markdown plain-control 256x incremental edit+restore'
readonly -a case_labels=(
  'realistic'
  '50x'
  'delimiter 64x full parse'
  'delimiter 64x incremental edit+restore'
  'delimiter 256x full parse'
  'delimiter 256x incremental edit+restore'
)
readonly -a case_controls=(
  "$realistic_direct"
  "$scaled_direct"
  "$plain_64_full"
  "$plain_64_incremental"
  "$plain_256_full"
  "$plain_256_incremental"
)
readonly -a case_subjects=(
  "$realistic_ir"
  "$scaled_ir"
  "$delimiter_64_full"
  "$delimiter_64_incremental"
  "$delimiter_256_full"
  "$delimiter_256_incremental"
)
readonly -a case_policies=(
  'legacy'
  'legacy'
  'delimiter'
  'delimiter'
  'delimiter'
  'delimiter'
)
readonly -a case_control_displays=(
  'direct'
  'direct'
  'plain-control'
  'plain-control'
  'plain-control'
  'plain-control'
)
readonly -a case_subject_displays=(
  'IR'
  'IR'
  'subject'
  'subject'
  'subject'
  'subject'
)
readonly case_count="${#case_labels[@]}"

usage() {
  cat >&2 <<'EOF'
Usage: markdown-ir-perf-guard.sh BASE_1 HEAD_1 BASE_2 HEAD_2 BASE_3 HEAD_3

Each argument is raw `moon bench` output containing the four Markdown lowering
benchmarks and eight delimiter/plain-control benchmarks. Exit 0 means no
persistent regression, 1 means regression, and 2 means the comparison input or
verifier is invalid.

MARKDOWN_IR_PERF_HARD_CEILING_PERCENT=100 is the default inclusive raw-slowdown
ceiling. Override it with a positive percentage when runner policy requires it.
MARKDOWN_DIRECT_PERF_THRESHOLD_PERCENT=50 is the default persistent direct
Block-lowering slowdown threshold.

Delimiter thresholds have no defaults until A/A calibration is recorded. Set
MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT,
MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT, and
MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT together to enable delimiter
gating. When all three are unset, delimiter rows remain required and their
deltas are printed in calibration mode without a performance verdict.
MARKDOWN_DELIMITER_PERF_CALIBRATION=1 explicitly disables only the delimiter
performance verdict so exact A/A trials can be repeated after defaults exist.
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
if [[ ! "$direct_threshold_percent" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  infra_fail "MARKDOWN_DIRECT_PERF_THRESHOLD_PERCENT must be a non-negative number"
fi
if [[ "$delimiter_calibration" != 0 && "$delimiter_calibration" != 1 ]]; then
  infra_fail "MARKDOWN_DELIMITER_PERF_CALIBRATION must be 0 or 1"
fi
delimiter_gated=0
if [[ -z "$delimiter_threshold_percent" &&
      -z "$delimiter_hard_ceiling_percent" &&
      -z "$delimiter_control_threshold_percent" ]]; then
  delimiter_gated=0
elif [[ -z "$delimiter_threshold_percent" ||
        -z "$delimiter_hard_ceiling_percent" ||
        -z "$delimiter_control_threshold_percent" ]]; then
  infra_fail "set all three MARKDOWN_DELIMITER_*_PERCENT variables together, or leave all three unset for calibration"
else
  if [[ ! "$delimiter_threshold_percent" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    infra_fail "MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT must be a non-negative number"
  fi
  if [[ ! "$delimiter_hard_ceiling_percent" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
    ! awk -v value="$delimiter_hard_ceiling_percent" 'BEGIN { exit !(value > 0) }'; then
    infra_fail "MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT must be a positive number"
  fi
  if [[ ! "$delimiter_control_threshold_percent" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    infra_fail "MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT must be a non-negative number"
  fi
  delimiter_gated=1
fi
if [[ "$delimiter_calibration" == 1 ]]; then
  delimiter_gated=0
fi
readonly delimiter_gated

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
for ((case_index = 0; case_index < case_count; case_index++)); do
  printf '%s\n' "${case_controls[$case_index]}"
  printf '%s\n' "${case_subjects[$case_index]}"
done > "$work_dir/expected-benchmarks.txt"

parse_bench_output() {
  local input="$1" label="$2" output="$3"
  [[ -f "$input" ]] || {
    printf '%s: benchmark output file not found: %s\n' "$label" "$input" >&2
    return 1
  }
  awk \
    -v label="$label" \
    -v expected_benchmarks="$work_dir/expected-benchmarks.txt" '
    BEGIN {
      while ((getline name < expected_benchmarks) > 0) wanted[name] = 1
      close(expected_benchmarks)
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

case_bad=0
case_control_bad=0
case_bad_counts=()
case_control_bad_counts=()
for ((case_index = 0; case_index < case_count; case_index++)); do
  case_bad_counts+=(0)
  case_control_bad_counts+=(0)
done

printf 'Markdown lowering PR performance guard (IR threshold: +%s%% raw+normalized; IR hard ceiling: >=+%s%% raw; direct threshold: +%s%% raw; persistence: %s/%s)\n' \
  "$threshold_percent" "$hard_ceiling_percent" "$direct_threshold_percent" \
  "$trial_pairs" "$trial_pairs"
if [[ "$delimiter_gated" -eq 1 ]]; then
  printf 'Delimiter performance gate (subject threshold: +%s%% raw+normalized; hard ceiling: >=+%s%% raw; plain-control threshold: +%s%% raw; persistence: %s/%s)\n' \
    "$delimiter_threshold_percent" "$delimiter_hard_ceiling_percent" \
    "$delimiter_control_threshold_percent" "$trial_pairs" "$trial_pairs"
elif [[ "$delimiter_calibration" == 1 ]]; then
  printf 'CALIBRATION: delimiter verdict disabled explicitly; recording deltas only\n'
else
  printf 'CALIBRATION: delimiter thresholds unset; recording deltas without a delimiter performance verdict\n'
fi

check_case() {
  local trial="$1" label="$2" control_name="$3" subject_name="$4"
  local control_display="$5" subject_display="$6" gated="$7"
  local subject_threshold="$8" subject_hard_ceiling="$9"
  local control_threshold="${10}"
  local base_tsv="$work_dir/base-$trial.tsv" head_tsv="$work_dir/head-$trial.tsv"
  local base_control_value base_subject_value head_control_value head_subject_value metrics
  base_control_value=$(read_value "$base_tsv" "$control_name")
  base_subject_value=$(read_value "$base_tsv" "$subject_name")
  head_control_value=$(read_value "$head_tsv" "$control_name")
  head_subject_value=$(read_value "$head_tsv" "$subject_name")

  metrics=$(awk \
    -v bc="$base_control_value" -v bs="$base_subject_value" \
    -v hc="$head_control_value" -v hs="$head_subject_value" \
    -v gated="$gated" \
    -v threshold="$subject_threshold" \
    -v hard_ceiling="$subject_hard_ceiling" \
    -v control_threshold="$control_threshold" '
      BEGIN {
        if (bc <= 0 || bs <= 0 || hc <= 0 || hs <= 0) exit 2
        raw = (hs / bs - 1) * 100
        normalized = ((hs / hc) / (bs / bc) - 1) * 100
        control = (hc / bc - 1) * 100
        bad = 0
        hard_bad = 0
        control_bad = 0
        if (gated) {
          relative_bad = raw > threshold && normalized > threshold
          hard_bad = raw >= hard_ceiling
          control_bad = control > control_threshold
          bad = relative_bad || hard_bad
        }
        printf "%.1f\t%.1f\t%d\t%d\t%.1f\t%d", raw, normalized, bad, hard_bad, control, control_bad
      }
    ') || \
    infra_fail "non-positive or invalid measurement in trial $trial ($label)"

  local raw_percent normalized_percent bad hard_bad control_percent control_bad status
  IFS=$'\t' read -r raw_percent normalized_percent bad hard_bad control_percent control_bad <<< "$metrics"
  status=ok
  if [[ "$gated" == 0 ]]; then
    status=CALIBRATION
  elif [[ "$hard_bad" == 1 ]]; then
    status='BAD (hard ceiling)'
  elif [[ "$bad" == 1 ]]; then
    status=BAD
  elif [[ "$control_bad" == 1 ]]; then
    status="BAD ($control_display)"
  fi
  printf '  trial %s %-38s %s base/head %s/%s ns (%+.1f%%); %s %s/%s ns (%+.1f%%); normalized %+.1f%%; %s\n' \
    "$trial" "$label" "$control_display" "$base_control_value" \
    "$head_control_value" "$control_percent" "$subject_display" \
    "$base_subject_value" "$head_subject_value" "$raw_percent" \
    "$normalized_percent" "$status"
  case_bad="$bad"
  case_control_bad="$control_bad"
}

for trial in 1 2 3; do
  for ((case_index = 0; case_index < case_count; case_index++)); do
    if [[ "${case_policies[$case_index]}" == legacy ]]; then
      gated=1
      subject_threshold="$threshold_percent"
      subject_hard_ceiling="$hard_ceiling_percent"
      control_threshold="$direct_threshold_percent"
    else
      gated="$delimiter_gated"
      subject_threshold="${delimiter_threshold_percent:-0}"
      subject_hard_ceiling="${delimiter_hard_ceiling_percent:-0}"
      control_threshold="${delimiter_control_threshold_percent:-0}"
    fi
    check_case \
      "$trial" \
      "${case_labels[$case_index]}" \
      "${case_controls[$case_index]}" \
      "${case_subjects[$case_index]}" \
      "${case_control_displays[$case_index]}" \
      "${case_subject_displays[$case_index]}" \
      "$gated" \
      "$subject_threshold" \
      "$subject_hard_ceiling" \
      "$control_threshold"
    case_bad_counts[case_index]=$((case_bad_counts[case_index] + case_bad))
    case_control_bad_counts[case_index]=$((case_control_bad_counts[case_index] + case_control_bad))
  done
done

bad_realistic="${case_bad_counts[0]}"
bad_scaled="${case_bad_counts[1]}"
bad_direct_realistic="${case_control_bad_counts[0]}"
bad_direct_scaled="${case_control_bad_counts[1]}"

failed=0
if [[ "$bad_realistic" -eq "$trial_pairs" || "$bad_scaled" -eq "$trial_pairs" ]]; then
  printf 'FAIL: persistent MarkdownIR lowering regression'
  [[ "$bad_realistic" -eq "$trial_pairs" ]] && printf ' [realistic]'
  [[ "$bad_scaled" -eq "$trial_pairs" ]] && printf ' [50x]'
  printf '\n'
  failed=1
fi
if [[ "$bad_direct_realistic" -eq "$trial_pairs" ||
      "$bad_direct_scaled" -eq "$trial_pairs" ]]; then
  printf 'FAIL: persistent direct Block lowering regression'
  [[ "$bad_direct_realistic" -eq "$trial_pairs" ]] && printf ' [realistic]'
  [[ "$bad_direct_scaled" -eq "$trial_pairs" ]] && printf ' [50x]'
  printf '\n'
  failed=1
fi
delimiter_failed=0
for ((case_index = 2; case_index < case_count; case_index++)); do
  if [[ "${case_bad_counts[$case_index]}" -eq "$trial_pairs" ]]; then
    if [[ "$delimiter_failed" -eq 0 ]]; then
      printf 'FAIL: persistent delimiter-heavy regression'
    fi
    printf ' [%s]' "${case_labels[$case_index]#delimiter }"
    delimiter_failed=1
  fi
done
if [[ "$delimiter_failed" -eq 1 ]]; then
  printf '\n'
  failed=1
fi
delimiter_control_failed=0
for ((case_index = 2; case_index < case_count; case_index++)); do
  if [[ "${case_control_bad_counts[$case_index]}" -eq "$trial_pairs" ]]; then
    if [[ "$delimiter_control_failed" -eq 0 ]]; then
      printf 'FAIL: persistent delimiter plain-control regression'
    fi
    printf ' [%s]' "${case_labels[$case_index]#delimiter }"
    delimiter_control_failed=1
  fi
done
if [[ "$delimiter_control_failed" -eq 1 ]]; then
  printf '\n'
  failed=1
fi
if [[ "$failed" -eq 1 ]]; then
  exit 1
fi

printf 'PASS: no persistent Markdown lowering regression'
has_non_persistent=0
if [[ "$bad_realistic" -gt 0 || "$bad_scaled" -gt 0 ||
      "$bad_direct_realistic" -gt 0 || "$bad_direct_scaled" -gt 0 ]]; then
  has_non_persistent=1
fi
for ((case_index = 2; case_index < case_count; case_index++)); do
  if [[ "${case_bad_counts[$case_index]}" -gt 0 ||
        "${case_control_bad_counts[$case_index]}" -gt 0 ]]; then
    has_non_persistent=1
  fi
done
if [[ "$has_non_persistent" -eq 1 ]]; then
  printf ' (non-persistent observations: IR realistic=%s/%s, IR 50x=%s/%s, direct realistic=%s/%s, direct 50x=%s/%s' \
    "$bad_realistic" "$trial_pairs" "$bad_scaled" "$trial_pairs" \
    "$bad_direct_realistic" "$trial_pairs" "$bad_direct_scaled" "$trial_pairs"
  for ((case_index = 2; case_index < case_count; case_index++)); do
    if [[ "${case_bad_counts[$case_index]}" -gt 0 ]]; then
      printf ', %s=%s/%s' "${case_labels[$case_index]}" \
        "${case_bad_counts[$case_index]}" "$trial_pairs"
    fi
    if [[ "${case_control_bad_counts[$case_index]}" -gt 0 ]]; then
      printf ', plain-control %s=%s/%s' \
        "${case_labels[$case_index]#delimiter }" \
        "${case_control_bad_counts[$case_index]}" "$trial_pairs"
    fi
  done
  printf ')'
fi
printf '\n'
