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
readonly delimiter_threshold_percent="${MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT:-50}"
readonly delimiter_hard_ceiling_percent="${MARKDOWN_DELIMITER_PERF_HARD_CEILING_PERCENT:-100}"
readonly delimiter_control_threshold_percent="${MARKDOWN_DELIMITER_CONTROL_PERF_THRESHOLD_PERCENT:-50}"
readonly source_bound_threshold_percent="${MARKDOWN_SOURCE_BOUND_PERF_THRESHOLD_PERCENT:-100}"
readonly source_bound_hard_ceiling_percent="${MARKDOWN_SOURCE_BOUND_PERF_HARD_CEILING_PERCENT:-200}"
readonly source_bound_control_threshold_percent="${MARKDOWN_SOURCE_BOUND_CONTROL_PERF_THRESHOLD_PERCENT:-50}"
readonly delimiter_calibration="${MARKDOWN_DELIMITER_PERF_CALIBRATION:-0}"
readonly source_bound_calibration="${MARKDOWN_SOURCE_BOUND_PERF_CALIBRATION:-0}"
readonly verbose="${MARKDOWN_PERF_GUARD_VERBOSE:-0}"
readonly complexity_source_growth_ceiling="${MARKDOWN_COMPLEXITY_SOURCE_GROWTH_CEILING:-8}"
readonly complexity_depth_growth_ceiling="${MARKDOWN_COMPLEXITY_DEPTH_GROWTH_CEILING:-100}"
readonly complexity_calibration="${MARKDOWN_COMPLEXITY_PERF_CALIBRATION:-1}"
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
readonly source_bound_control='perf source-bound benchmark control'
readonly source_bound_parse='perf source-bound parse_document 100 paragraphs'
readonly source_bound_semantic='perf source-bound semantic_read 100 paragraphs'
readonly source_bound_block='perf source-bound Block adapter 100 paragraphs'
readonly source_bound_mdast='perf source-bound mdast adapter 100 paragraphs'
readonly source_bound_preserve='perf source-bound preserve rewrite 100 paragraphs'
readonly source_bound_local='perf source-bound local rewrite selection'
readonly source_bound_ir_only='perf source-bound IR-only target through read'
readonly source_bound_attachment='perf source-bound attachment source_document'
readonly complexity_opener_small='markdown adversarial unmatched opener small full parse'
readonly complexity_control_small='markdown adversarial unmatched opener small plain control'
readonly complexity_opener_large='markdown adversarial unmatched opener large full parse'
readonly complexity_control_large='markdown adversarial unmatched opener large plain control'
readonly complexity_nested_32='markdown adversarial nested-link depth 32 full parse'
readonly complexity_nested_48='markdown adversarial nested-link depth 48 full parse'

readonly -a case_labels=(
  'realistic'
  '50x'
  'delimiter 64x full parse'
  'delimiter 64x incremental edit+restore'
  'delimiter 256x full parse'
  'delimiter 256x incremental edit+restore'
  'source-bound parse_document'
  'source-bound semantic_read'
  'source-bound Block adapter'
  'source-bound mdast adapter'
  'source-bound preserve rewrite'
  'source-bound local rewrite selection'
  'source-bound IR-only target'
  'source-bound attachment source_document'
)
readonly -a case_controls=(
  "$realistic_direct"
  "$scaled_direct"
  "$plain_64_full"
  "$plain_64_incremental"
  "$plain_256_full"
  "$plain_256_incremental"
  "$source_bound_control"
  "$source_bound_control"
  "$source_bound_control"
  "$source_bound_control"
  "$source_bound_control"
  "$source_bound_control"
  "$source_bound_control"
  "$source_bound_control"
)
readonly -a case_subjects=(
  "$realistic_ir"
  "$scaled_ir"
  "$delimiter_64_full"
  "$delimiter_64_incremental"
  "$delimiter_256_full"
  "$delimiter_256_incremental"
  "$source_bound_parse"
  "$source_bound_semantic"
  "$source_bound_block"
  "$source_bound_mdast"
  "$source_bound_preserve"
  "$source_bound_local"
  "$source_bound_ir_only"
  "$source_bound_attachment"
)
readonly -a case_policies=(
  'legacy'
  'legacy'
  'delimiter'
  'delimiter'
  'delimiter'
  'delimiter'
  'source-bound'
  'source-bound'
  'source-bound'
  'source-bound'
  'source-bound'
  'source-bound'
  'source-bound'
  'source-bound'
)
readonly -a case_control_displays=(
  'direct'
  'direct'
  'plain-control'
  'plain-control'
  'plain-control'
  'plain-control'
  'source-bound control'
  'source-bound control'
  'source-bound control'
  'source-bound control'
  'source-bound control'
  'source-bound control'
  'source-bound control'
  'source-bound control'
)
readonly -a case_subject_displays=(
  'IR'
  'IR'
  'subject'
  'subject'
  'subject'
  'subject'
  'parse_document'
  'semantic_read'
  'Block adapter'
  'mdast adapter'
  'preserve rewrite'
  'local rewrite'
  'IR-only target'
  'attachment source_document'
)

readonly case_count="${#case_labels[@]}"
usage() {
  cat >&2 <<'EOF'
Usage: markdown-ir-perf-guard.sh BASE_1 HEAD_1 BASE_2 HEAD_2 BASE_3 HEAD_3

Each argument is raw `moon bench` output containing the four Markdown lowering,
eight delimiter/plain-control benchmarks, the source-bound control plus eight
source-bound benchmarks, and six adversarial-complexity benchmarks. Exit 0
means no persistent regression, 1 means regression, and 2 means the comparison
input or verifier is invalid.

MARKDOWN_IR_PERF_HARD_CEILING_PERCENT=100 is the default inclusive raw-slowdown
ceiling. Override it with a positive percentage when runner policy requires it.
MARKDOWN_DIRECT_PERF_THRESHOLD_PERCENT=50 is the default persistent direct
Block-lowering slowdown threshold.

MARKDOWN_DELIMITER_PERF_THRESHOLD_PERCENT=50 is the default delimiter subject
raw-and-normalized threshold. The inclusive delimiter raw hard ceiling defaults
to 100%, and the independent plain-control threshold defaults to 50%.
MARKDOWN_DELIMITER_PERF_CALIBRATION=1 explicitly disables only the delimiter
performance verdict so exact A/A trials can be repeated after defaults exist.

MARKDOWN_SOURCE_BOUND_PERF_THRESHOLD_PERCENT=100 is the default source-bound
subject raw-and-normalized threshold. The inclusive source-bound raw hard
ceiling defaults to 200%, and its control threshold defaults to 50%.
MARKDOWN_SOURCE_BOUND_PERF_CALIBRATION=1 explicitly disables only the
source-bound performance verdict so pre-document legacy-vs-current rows can be
reported as cutover characterization without weakening current-adapter gates.

MARKDOWN_COMPLEXITY_SOURCE_GROWTH_CEILING=8 is the candidate inclusive ceiling
for both unmatched-opener and equal-length plain-control 4x source growth.
MARKDOWN_COMPLEXITY_DEPTH_GROWTH_CEILING=100 is the candidate inclusive ceiling
for nested-link depth 32-to-48 growth. MARKDOWN_COMPLEXITY_PERF_CALIBRATION=1
is the default and keeps both verdicts non-gating while recording ratios.
MARKDOWN_PERF_GUARD_VERBOSE=1 prints every base/head trial row; the default
output prints only the compact result and expands details on failure.
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
if [[ "$source_bound_calibration" != 0 && "$source_bound_calibration" != 1 ]]; then
  infra_fail "MARKDOWN_SOURCE_BOUND_PERF_CALIBRATION must be 0 or 1"
fi
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
if [[ ! "$source_bound_threshold_percent" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  infra_fail "MARKDOWN_SOURCE_BOUND_PERF_THRESHOLD_PERCENT must be a non-negative number"
fi
if [[ ! "$source_bound_hard_ceiling_percent" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
  ! awk -v value="$source_bound_hard_ceiling_percent" 'BEGIN { exit !(value > 0) }'; then
  infra_fail "MARKDOWN_SOURCE_BOUND_PERF_HARD_CEILING_PERCENT must be a positive number"
fi
if [[ ! "$source_bound_control_threshold_percent" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  infra_fail "MARKDOWN_SOURCE_BOUND_CONTROL_PERF_THRESHOLD_PERCENT must be a non-negative number"
fi
if [[ "$complexity_calibration" != 0 && "$complexity_calibration" != 1 ]]; then
  infra_fail "MARKDOWN_COMPLEXITY_PERF_CALIBRATION must be 0 or 1"
fi
if [[ ! "$complexity_source_growth_ceiling" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
  ! awk -v value="$complexity_source_growth_ceiling" 'BEGIN { exit !(value > 0) }'; then
  infra_fail "MARKDOWN_COMPLEXITY_SOURCE_GROWTH_CEILING must be a positive number"
fi
if [[ ! "$complexity_depth_growth_ceiling" =~ ^[0-9]+([.][0-9]+)?$ ]] ||
  ! awk -v value="$complexity_depth_growth_ceiling" 'BEGIN { exit !(value > 0) }'; then
  infra_fail "MARKDOWN_COMPLEXITY_DEPTH_GROWTH_CEILING must be a positive number"
fi
delimiter_gated=1
if [[ "$delimiter_calibration" == 1 ]]; then
  delimiter_gated=0
fi
readonly delimiter_gated
source_bound_gated=1
if [[ "$source_bound_calibration" == 1 ]]; then
  source_bound_gated=0
fi
readonly source_bound_gated
complexity_gated=1
if [[ "$complexity_calibration" == 1 ]]; then
  complexity_gated=0
fi
readonly complexity_gated

work_dir=$(mktemp -d)
details_file="$work_dir/trial-details.txt"
calibration_file="$work_dir/calibration.tsv"
complexity_calibration_file="$work_dir/complexity-calibration.tsv"
trap 'rm -rf "$work_dir"' EXIT
for ((case_index = 0; case_index < case_count; case_index++)); do
  printf '%s\n' "${case_controls[$case_index]}"
  printf '%s\n' "${case_subjects[$case_index]}"
done > "$work_dir/expected-benchmarks.txt"
cat >> "$work_dir/expected-benchmarks.txt" <<EOF
$complexity_opener_small
$complexity_control_small
$complexity_opener_large
$complexity_control_large
$complexity_nested_32
$complexity_nested_48
EOF

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
complexity_head_subject_bad_count=0
complexity_head_control_bad_count=0
complexity_head_depth_bad_count=0

if [[ "$verbose" == 1 ]]; then
  printf 'Markdown lowering PR performance guard (IR threshold: +%s%% raw+normalized; IR hard ceiling: >=+%s%% raw; direct threshold: +%s%% raw; persistence: %s/%s)\n' \
    "$threshold_percent" "$hard_ceiling_percent" "$direct_threshold_percent" \
    "$trial_pairs" "$trial_pairs"
  if [[ "$delimiter_gated" -eq 1 ]]; then
    printf 'Delimiter performance gate (subject threshold: +%s%% raw+normalized; hard ceiling: >=+%s%% raw; plain-control threshold: +%s%% raw; persistence: %s/%s)\n' \
      "$delimiter_threshold_percent" "$delimiter_hard_ceiling_percent" \
      "$delimiter_control_threshold_percent" "$trial_pairs" "$trial_pairs"
  elif [[ "$delimiter_calibration" == 1 ]]; then
    printf 'CALIBRATION: delimiter verdict disabled explicitly; recording deltas only\n'
  fi
  if [[ "$source_bound_gated" -eq 1 ]]; then
    printf 'Source-bound performance gate (subject threshold: +%s%% raw+normalized; hard ceiling: >=+%s%% raw; control threshold: +%s%% raw; persistence: %s/%s)\n' \
      "$source_bound_threshold_percent" "$source_bound_hard_ceiling_percent" \
      "$source_bound_control_threshold_percent" "$trial_pairs" "$trial_pairs"
  else
    printf 'CALIBRATION: source-bound verdict disabled explicitly; recording deltas only\n'
  fi
  if [[ "$complexity_gated" -eq 1 ]]; then
    printf 'Markdown complexity gate (source growth ceiling: >=%sx; depth growth ceiling: >=%sx; persistence: %s/%s)\n' \
      "$complexity_source_growth_ceiling" "$complexity_depth_growth_ceiling" \
      "$trial_pairs" "$trial_pairs"
  else
    printf 'CALIBRATION: Markdown complexity verdict disabled; recording scale ratios only\n'
  fi
else
  if [[ "$delimiter_calibration" == 1 &&
        "$source_bound_calibration" == 1 ]]; then
    printf 'Markdown performance: %s alternating base/head trials; IR +%s%%; delimiter calibration (non-gating); source-bound calibration (non-gating)\n' \
      "$trial_pairs" "$threshold_percent"
  elif [[ "$delimiter_calibration" == 1 ]]; then
    printf 'Markdown performance: %s alternating base/head trials; IR +%s%%; delimiter calibration (non-gating); source-bound +%s%%\n' \
      "$trial_pairs" "$threshold_percent" "$source_bound_threshold_percent"
  elif [[ "$source_bound_calibration" == 1 ]]; then
    printf 'Markdown performance: %s alternating base/head trials; IR +%s%%; delimiter +%s%%; source-bound calibration (non-gating)\n' \
      "$trial_pairs" "$threshold_percent" "$delimiter_threshold_percent"
  else
    printf 'Markdown performance: %s alternating base/head trials; IR +%s%%; delimiter +%s%%; source-bound +%s%%\n' \
      "$trial_pairs" "$threshold_percent" "$delimiter_threshold_percent" \
      "$source_bound_threshold_percent"
  fi
fi
if [[ "$verbose" != 1 ]]; then
  if [[ "$complexity_gated" -eq 1 ]]; then
    printf 'Markdown complexity: source <%sx; depth <%sx; persistence %s/%s\n' \
      "$complexity_source_growth_ceiling" "$complexity_depth_growth_ceiling" \
      "$trial_pairs" "$trial_pairs"
  else
    printf 'Markdown complexity: calibration (non-gating)\n'
  fi
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
  if [[ "$gated" == 0 ]]; then
    printf '%s\t%s\t%s\n' "$label" "$raw_percent" "$normalized_percent" >> "$calibration_file"
  fi
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
    "$normalized_percent" "$status" >> "$details_file"
  case_bad="$bad"
  case_control_bad="$control_bad"
}
check_complexity_trial() {
  local trial="$1"
  local base_tsv="$work_dir/base-$trial.tsv" head_tsv="$work_dir/head-$trial.tsv"
  local base_opener_small base_opener_large base_control_small base_control_large
  local base_nested_32 base_nested_48 head_opener_small head_opener_large
  local head_control_small head_control_large head_nested_32 head_nested_48 metrics
  base_opener_small=$(read_value "$base_tsv" "$complexity_opener_small")
  base_opener_large=$(read_value "$base_tsv" "$complexity_opener_large")
  base_control_small=$(read_value "$base_tsv" "$complexity_control_small")
  base_control_large=$(read_value "$base_tsv" "$complexity_control_large")
  base_nested_32=$(read_value "$base_tsv" "$complexity_nested_32")
  base_nested_48=$(read_value "$base_tsv" "$complexity_nested_48")
  head_opener_small=$(read_value "$head_tsv" "$complexity_opener_small")
  head_opener_large=$(read_value "$head_tsv" "$complexity_opener_large")
  head_control_small=$(read_value "$head_tsv" "$complexity_control_small")
  head_control_large=$(read_value "$head_tsv" "$complexity_control_large")
  head_nested_32=$(read_value "$head_tsv" "$complexity_nested_32")
  head_nested_48=$(read_value "$head_tsv" "$complexity_nested_48")

  metrics=$(awk \
    -v bos="$base_opener_small" -v bol="$base_opener_large" \
    -v bcs="$base_control_small" -v bcl="$base_control_large" \
    -v bn32="$base_nested_32" -v bn48="$base_nested_48" \
    -v hos="$head_opener_small" -v hol="$head_opener_large" \
    -v hcs="$head_control_small" -v hcl="$head_control_large" \
    -v hn32="$head_nested_32" -v hn48="$head_nested_48" \
    -v source_ceiling="$complexity_source_growth_ceiling" \
    -v depth_ceiling="$complexity_depth_growth_ceiling" '
      BEGIN {
        if (bos <= 0 || bol <= 0 || bcs <= 0 || bcl <= 0 ||
            bn32 <= 0 || bn48 <= 0 || hos <= 0 || hol <= 0 ||
            hcs <= 0 || hcl <= 0 || hn32 <= 0 || hn48 <= 0) exit 2
        bs = bol / bos
        bc = bcl / bcs
        bd = bn48 / bn32
        hs = hol / hos
        hc = hcl / hcs
        hd = hn48 / hn32
        bn = bs / bc
        hn = hs / hc
        printf "%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%d\t%d\t%d", \
          bs, bc, bn, bd, hs, hc, hn, hd, \
          (hs >= source_ceiling), (hc >= source_ceiling), (hd >= depth_ceiling)
      }
    ') || infra_fail "non-positive or invalid complexity measurement in trial $trial"

  local bs bc bn bd hs hc hn hd hsb hcb hdb status
  IFS=$'\t' read -r bs bc bn bd hs hc hn hd hsb hcb hdb <<< "$metrics"
  complexity_head_subject_bad_count=$((complexity_head_subject_bad_count + hsb))
  complexity_head_control_bad_count=$((complexity_head_control_bad_count + hcb))
  complexity_head_depth_bad_count=$((complexity_head_depth_bad_count + hdb))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$trial" "$bs" "$bc" "$bn" "$bd" "$hs" "$hc" "$hn" "$hd" \
    >> "$complexity_calibration_file"
  status=ok
  if [[ "$complexity_gated" -eq 0 ]]; then
    status=CALIBRATION
  elif [[ "$hsb" -eq 1 || "$hcb" -eq 1 || "$hdb" -eq 1 ]]; then
    status=BAD
  fi
  printf '  trial %s %-38s base subject/control/normalized/depth %s/%s/%s/%s x; head %s/%s/%s/%s x; %s\n' \
    "$trial" "Markdown adversarial complexity" "$bs" "$bc" "$bn" "$bd" \
    "$hs" "$hc" "$hn" "$hd" "$status" >> "$details_file"
}


for trial in 1 2 3; do
  for ((case_index = 0; case_index < case_count; case_index++)); do
    if [[ "${case_policies[$case_index]}" == legacy ]]; then
      gated=1
      subject_threshold="$threshold_percent"
      subject_hard_ceiling="$hard_ceiling_percent"
      control_threshold="$direct_threshold_percent"
    elif [[ "${case_policies[$case_index]}" == delimiter ]]; then
      gated="$delimiter_gated"
      subject_threshold="$delimiter_threshold_percent"
      subject_hard_ceiling="$delimiter_hard_ceiling_percent"
      control_threshold="$delimiter_control_threshold_percent"
    else
      gated="$source_bound_gated"
      subject_threshold="$source_bound_threshold_percent"
      subject_hard_ceiling="$source_bound_hard_ceiling_percent"
      control_threshold="$source_bound_control_threshold_percent"
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
for trial in 1 2 3; do
  check_complexity_trial "$trial"
done

bad_realistic="${case_bad_counts[0]}"
bad_scaled="${case_bad_counts[1]}"
bad_direct_realistic="${case_control_bad_counts[0]}"
bad_direct_scaled="${case_control_bad_counts[1]}"

failed=0
if [[ "$complexity_gated" -eq 1 ]]; then
  if [[ "$complexity_head_subject_bad_count" -eq "$trial_pairs" ]]; then
    printf 'FAIL: persistent unmatched-opener growth violation\n'
    failed=1
  fi
  if [[ "$complexity_head_control_bad_count" -eq "$trial_pairs" ]]; then
    printf 'FAIL: persistent plain-control growth violation\n'
    failed=1
  fi
  if [[ "$complexity_head_depth_bad_count" -eq "$trial_pairs" ]]; then
    printf 'FAIL: persistent nested-link depth-growth violation\n'
    failed=1
  fi
fi
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
for ((case_index = 0; case_index < case_count; case_index++)); do
  [[ "${case_policies[$case_index]}" == delimiter ]] || continue
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
for ((case_index = 0; case_index < case_count; case_index++)); do
  [[ "${case_policies[$case_index]}" == delimiter ]] || continue
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
source_bound_failed=0
for ((case_index = 0; case_index < case_count; case_index++)); do
  [[ "${case_policies[$case_index]}" == source-bound ]] || continue
  if [[ "${case_bad_counts[$case_index]}" -eq "$trial_pairs" ]]; then
    if [[ "$source_bound_failed" -eq 0 ]]; then
      printf 'FAIL: persistent source-bound regression'
    fi
    printf ' [%s]' "${case_labels[$case_index]#source-bound }"
    source_bound_failed=1
  fi
done
if [[ "$source_bound_failed" -eq 1 ]]; then
  printf '\n'
  failed=1
fi
source_bound_control_failed=0
for ((case_index = 0; case_index < case_count; case_index++)); do
  [[ "${case_policies[$case_index]}" == source-bound ]] || continue
  if [[ "${case_control_bad_counts[$case_index]}" -eq "$trial_pairs" ]]; then
    if [[ "$source_bound_control_failed" -eq 0 ]]; then
      printf 'FAIL: persistent source-bound control regression'
    fi
    printf ' [%s]' "${case_labels[$case_index]#source-bound }"
    source_bound_control_failed=1
  fi
done
if [[ "$source_bound_control_failed" -eq 1 ]]; then
  printf '\n'
  failed=1
fi
if [[ "$delimiter_calibration" == 1 && "$verbose" != 1 ]]; then
  printf 'CALIBRATION: delimiter verdict disabled; raw/normalized deltas over %s trials\n' \
    "$trial_pairs"
  for ((case_index = 0; case_index < case_count; case_index++)); do
    [[ "${case_policies[$case_index]}" == delimiter ]] || continue
    label="${case_labels[$case_index]}"
    calibration_metrics=$(awk -F '\t' -v label="$label" '
      $1 == label {
        if (count == 0 || $2 < raw_min) raw_min = $2
        if (count == 0 || $2 > raw_max) raw_max = $2
        if (count == 0 || $3 < normalized_min) normalized_min = $3
        if (count == 0 || $3 > normalized_max) normalized_max = $3
        count++
      }
      END {
        if (count > 0) {
          printf "%.1f\t%.1f\t%.1f\t%.1f", raw_min, raw_max, normalized_min, normalized_max
        }
      }
    ' "$calibration_file")
    IFS=$'\t' read -r raw_min raw_max normalized_min normalized_max <<< "$calibration_metrics"
    printf '  %s raw %+.1f..%+.1f%%; normalized %+.1f..%+.1f%%\n' \
      "$label" "$raw_min" "$raw_max" "$normalized_min" "$normalized_max"
  done
fi
if [[ "$source_bound_calibration" == 1 && "$verbose" != 1 ]]; then
  printf 'CALIBRATION: source-bound verdict disabled; raw/normalized deltas over %s trials\n' \
    "$trial_pairs"
  for ((case_index = 0; case_index < case_count; case_index++)); do
    [[ "${case_policies[$case_index]}" == source-bound ]] || continue
    label="${case_labels[$case_index]}"
    calibration_metrics=$(awk -F '\t' -v label="$label" '
      $1 == label {
        if (count == 0 || $2 < raw_min) raw_min = $2
        if (count == 0 || $2 > raw_max) raw_max = $2
        if (count == 0 || $3 < normalized_min) normalized_min = $3
        if (count == 0 || $3 > normalized_max) normalized_max = $3
        count++
      }
      END {
        if (count > 0) {
          printf "%.1f\t%.1f\t%.1f\t%.1f", raw_min, raw_max, normalized_min, normalized_max
        }
      }
    ' "$calibration_file")
    IFS=$'\t' read -r raw_min raw_max normalized_min normalized_max <<< "$calibration_metrics"
    printf '  %s raw %+.1f..%+.1f%%; normalized %+.1f..%+.1f%%\n' \
      "$label" "$raw_min" "$raw_max" "$normalized_min" "$normalized_max"
  done
fi
if [[ "$complexity_calibration" == 1 && "$verbose" != 1 ]]; then
  printf 'CALIBRATION: Markdown complexity verdict disabled; ratio ranges over %s trials\n' \
    "$trial_pairs"
  awk -F '\t' '
    NR == 1 {
      for (i = 2; i <= 9; i++) min[i] = max[i] = $i
    }
    {
      for (i = 2; i <= 9; i++) {
        if ($i < min[i]) min[i] = $i
        if ($i > max[i]) max[i] = $i
      }
    }
    END {
      printf "  base subject %.3f..%.3f x; control %.3f..%.3f x; normalized %.3f..%.3f x; depth %.3f..%.3f x\n", \
        min[2], max[2], min[3], max[3], min[4], max[4], min[5], max[5]
      printf "  head subject %.3f..%.3f x; control %.3f..%.3f x; normalized %.3f..%.3f x; depth %.3f..%.3f x\n", \
        min[6], max[6], min[7], max[7], min[8], max[8], min[9], max[9]
    }
  ' "$complexity_calibration_file"
fi
if [[ "$verbose" == 1 || "$failed" -eq 1 ]]; then
  cat "$details_file"
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
for ((case_index = 0; case_index < case_count; case_index++)); do
  [[ "${case_policies[$case_index]}" == delimiter ||
     "${case_policies[$case_index]}" == source-bound ]] || continue
  if [[ "${case_bad_counts[$case_index]}" -gt 0 ||
        "${case_control_bad_counts[$case_index]}" -gt 0 ]]; then
    has_non_persistent=1
  fi
done
if [[ "$complexity_gated" -eq 1 ]] &&
  (( (complexity_head_subject_bad_count > 0 &&
       complexity_head_subject_bad_count < trial_pairs) ||
     (complexity_head_control_bad_count > 0 &&
       complexity_head_control_bad_count < trial_pairs) ||
     (complexity_head_depth_bad_count > 0 &&
       complexity_head_depth_bad_count < trial_pairs) )); then
  has_non_persistent=1
fi
if [[ "$has_non_persistent" -eq 1 ]]; then
  printf ' (non-persistent observations: IR realistic=%s/%s, IR 50x=%s/%s, direct realistic=%s/%s, direct 50x=%s/%s' \
    "$bad_realistic" "$trial_pairs" "$bad_scaled" "$trial_pairs" \
    "$bad_direct_realistic" "$trial_pairs" "$bad_direct_scaled" "$trial_pairs"
  for ((case_index = 0; case_index < case_count; case_index++)); do
    if [[ "${case_policies[$case_index]}" == delimiter ]]; then
      if [[ "${case_bad_counts[$case_index]}" -gt 0 ]]; then
        printf ', %s=%s/%s' "${case_labels[$case_index]}" \
          "${case_bad_counts[$case_index]}" "$trial_pairs"
      fi
      if [[ "${case_control_bad_counts[$case_index]}" -gt 0 ]]; then
        printf ', plain-control %s=%s/%s' \
          "${case_labels[$case_index]#delimiter }" \
          "${case_control_bad_counts[$case_index]}" "$trial_pairs"
      fi
    elif [[ "${case_policies[$case_index]}" == source-bound ]]; then
      if [[ "${case_bad_counts[$case_index]}" -gt 0 ]]; then
        printf ', %s=%s/%s' "${case_labels[$case_index]}" \
          "${case_bad_counts[$case_index]}" "$trial_pairs"
      fi
      if [[ "${case_control_bad_counts[$case_index]}" -gt 0 ]]; then
        printf ', source-bound control %s=%s/%s' \
          "${case_labels[$case_index]#source-bound }" \
          "${case_control_bad_counts[$case_index]}" "$trial_pairs"
      fi
    fi
  done
  if [[ "$complexity_gated" -eq 1 ]]; then
    if [[ "$complexity_head_subject_bad_count" -gt 0 &&
          "$complexity_head_subject_bad_count" -lt "$trial_pairs" ]]; then
      printf ', unmatched-opener growth=%s/%s' \
        "$complexity_head_subject_bad_count" "$trial_pairs"
    fi
    if [[ "$complexity_head_control_bad_count" -gt 0 &&
          "$complexity_head_control_bad_count" -lt "$trial_pairs" ]]; then
      printf ', plain-control growth=%s/%s' \
        "$complexity_head_control_bad_count" "$trial_pairs"
    fi
    if [[ "$complexity_head_depth_bad_count" -gt 0 &&
          "$complexity_head_depth_bad_count" -lt "$trial_pairs" ]]; then
      printf ', nested-link depth growth=%s/%s' \
        "$complexity_head_depth_bad_count" "$trial_pairs"
    fi
  fi
  printf ')'
fi
printf '\n'
