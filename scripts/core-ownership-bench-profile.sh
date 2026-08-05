#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
policy_file="$repo_root/docs/performance/core-ownership-bench-policy.tsv"
checker="$repo_root/bench-check.sh"
target="wasm-gc"
baseline_ref=""
candidate_ref="HEAD"
runs=5
validate_only=false
artifact_dir="${CORE_OWNERSHIP_ARTIFACT_DIR:-}"

# Resolved relative to the checked-in runner root.
# shellcheck disable=SC1091
source "$repo_root/scripts/core-ownership-bench-lib.sh"

usage() {
  printf '%s\n' \
    'Usage: bash bench-check.sh --profile core-ownership --baseline-ref <sha> [--candidate-ref <sha>] [--runs 5]' \
    '       bash bench-check.sh --profile core-ownership --validate'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline-ref)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      baseline_ref="$2"
      shift 2
      ;;
    --candidate-ref)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      candidate_ref="$2"
      shift 2
      ;;
    --runs)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      runs="$2"
      shift 2
      ;;
    --validate)
      validate_only=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown core-ownership option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

core_ownership_validate_policy "$policy_file"
if "$validate_only"; then
  printf 'core-ownership policy is valid\n'
  exit 0
fi

if [[ -z "$baseline_ref" ]]; then
  printf '%s\n' '--baseline-ref is required for the core-ownership profile' >&2
  exit 2
fi
core_ownership_validate_release_runs "$runs"

baseline_sha=$(git -C "$repo_root" rev-parse --verify "${baseline_ref}^{commit}")
candidate_sha=$(git -C "$repo_root" rev-parse --verify "${candidate_ref}^{commit}")
if ! git -C "$repo_root" merge-base --is-ancestor "$baseline_sha" "$candidate_sha"; then
  printf 'Baseline %s is not an ancestor of candidate %s\n' "$baseline_sha" "$candidate_sha" >&2
  exit 1
fi
core_ownership_validate_runner_provenance "$repo_root" "$candidate_sha"
runner_sha=$(git -C "$repo_root" rev-parse HEAD)

if [[ -z "$artifact_dir" ]]; then
  artifact_dir=$(mktemp -d "${TMPDIR:-/tmp}/loom-core-ownership-artifacts.XXXXXX")
else
  mkdir -p "$artifact_dir"
  artifact_dir=$(cd "$artifact_dir" && pwd)
fi

worktree_parent=$(mktemp -d "${TMPDIR:-/tmp}/loom-core-ownership-worktrees.XXXXXX")
baseline_tree="$worktree_parent/baseline"
candidate_tree="$worktree_parent/candidate"

cleanup() {
  if [[ -d "$baseline_tree" ]]; then
    git -C "$repo_root" worktree remove --force "$baseline_tree" >/dev/null 2>&1 || true
  fi
  if [[ -d "$candidate_tree" ]]; then
    git -C "$repo_root" worktree remove --force "$candidate_tree" >/dev/null 2>&1 || true
  fi
  rmdir "$worktree_parent" >/dev/null 2>&1 || true
}
trap cleanup EXIT

git -C "$repo_root" worktree add --detach "$baseline_tree" "$baseline_sha" >/dev/null
git -C "$repo_root" worktree add --detach "$candidate_tree" "$candidate_sha" >/dev/null
git -C "$baseline_tree" submodule update --init --recursive
git -C "$candidate_tree" submodule update --init --recursive

capture_environment() {
  local tree="$1" output="$2" governor="unknown"
  if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
    governor=$(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
  fi
  {
    printf 'moon\t'
    (cd "$tree" && moon version 2>&1) | tr '\n' ';'
    printf '\n'
    printf 'target\t%s\n' "$target"
    printf 'machine\t%s\n' "$(uname -srm)"
    printf 'host\t%s\n' "$(hostname)"
    printf 'power\t%s\n' "$governor"
  } > "$output"
}

capture_environment "$baseline_tree" "$artifact_dir/baseline-environment.tsv"
capture_environment "$candidate_tree" "$artifact_dir/candidate-environment.tsv"
if ! core_ownership_environment_matches \
  "$artifact_dir/baseline-environment.tsv" \
  "$artifact_dir/candidate-environment.tsv"; then
  printf 'Baseline and candidate benchmark environments differ\n' >&2
  diff -u "$artifact_dir/baseline-environment.tsv" "$artifact_dir/candidate-environment.tsv" >&2 || true
  exit 1
fi

cp "$policy_file" "$artifact_dir/policy.tsv"
{
  printf 'baseline_sha\t%s\n' "$baseline_sha"
  printf 'candidate_sha\t%s\n' "$candidate_sha"
  printf 'runner_sha\t%s\n' "$runner_sha"
  printf 'runner_status\tclean\n'
  printf 'runs\t%s\n' "$runs"
  printf 'target\t%s\n' "$target"
} > "$artifact_dir/run-metadata.tsv"

manifest=$(printf '%s\n' \
  $'dowdiness/seam\tcore_ownership_bench_wbtest.mbt' \
  $'dowdiness/loom/core\tcore_ownership_bench_wbtest.mbt' \
  $'dowdiness/json\tbenchmark_test.mbt' \
  $'dowdiness/lambda/benchmarks\tbenchmark.mbt' \
  $'dowdiness/markdown\tmode_relex_storage_benchmark_wbtest.mbt' \
  $'dowdiness/markdown\tperformance_envelope_benchmark_test.mbt')

run_suite() {
  local tree="$1" side="$2" run="$3"
  local raw_file="$artifact_dir/${side}-run-${run}.raw.txt"
  local parsed_file="$artifact_dir/${side}-run-${run}.tsv"
  : > "$raw_file"
  : > "$parsed_file"
  while IFS=$'\t' read -r package file; do
    local command_output parsed_output
    command_output=$(mktemp "${TMPDIR:-/tmp}/loom-core-ownership-command.XXXXXX")
    printf '### moon bench -p %s -f %s --release --target %s\n' \
      "$package" "$file" "$target" >> "$raw_file"
    if ! (cd "$tree" && NEW_MOON_MOD=0 moon bench \
      -p "$package" -f "$file" --release --target "$target") \
      > "$command_output" 2>&1; then
      cat "$command_output" >> "$raw_file"
      rm -f "$command_output"
      printf '%s run %s failed: %s/%s\n' "$side" "$run" "$package" "$file" >&2
      return 1
    fi
    cat "$command_output" >> "$raw_file"
    if ! parsed_output=$(bash "$checker" --parse-bench-output < "$command_output"); then
      rm -f "$command_output"
      printf '%s run %s parse failed: %s/%s\n' "$side" "$run" "$package" "$file" >&2
      return 1
    fi
    rm -f "$command_output"
    if [[ -z "$parsed_output" ]]; then
      printf '%s run %s parsed zero rows: %s/%s\n' "$side" "$run" "$package" "$file" >&2
      return 1
    fi
    printf '%s\n' "$parsed_output" | awk -F '\t' -v package="$package" \
      '{ printf "%s::%s\t%s\n", package, $1, $2 }' >> "$parsed_file"
  done <<< "$manifest"

  bash "$checker" --validate-benchmark-tsv "$side run $run" < "$parsed_file"
  core_ownership_validate_required_rows "$policy_file" "$parsed_file" "$side run $run"
}

while IFS=$'\t' read -r side run; do
  tree="$baseline_tree"
  [[ "$side" == "candidate" ]] && tree="$candidate_tree"
  printf 'core-ownership: %s sample %d/%d\n' "$side" "$run" "$runs"
  run_suite "$tree" "$side" "$run"
done < <(core_ownership_schedule "$runs")

baseline_samples=()
candidate_samples=()
for ((run = 1; run <= runs; run++)); do
  baseline_samples+=("$artifact_dir/baseline-run-${run}.tsv")
  candidate_samples+=("$artifact_dir/candidate-run-${run}.tsv")
done

core_ownership_medians "$runs" "${baseline_samples[@]}" > "$artifact_dir/baseline-medians.tsv"
core_ownership_medians "$runs" "${candidate_samples[@]}" > "$artifact_dir/candidate-medians.tsv"
core_ownership_validate_required_rows "$policy_file" "$artifact_dir/baseline-medians.tsv" "baseline medians"
core_ownership_validate_required_rows "$policy_file" "$artifact_dir/candidate-medians.tsv" "candidate medians"

comparison="$artifact_dir/comparison.tsv"
if ! core_ownership_compare_medians "$policy_file" \
  "$artifact_dir/baseline-medians.tsv" \
  "$artifact_dir/candidate-medians.tsv" > "$comparison"; then
  cat "$comparison"
  printf 'core-ownership regression detected; artifacts: %s\n' "$artifact_dir" >&2
  exit 1
fi

cat "$comparison"
printf 'core-ownership comparison passed; artifacts: %s\n' "$artifact_dir"
