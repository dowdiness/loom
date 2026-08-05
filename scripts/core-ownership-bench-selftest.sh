#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
checker="$repo_root/bench-check.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

# Resolved relative to the checked-in runner root.
# shellcheck disable=SC1091
source "$repo_root/scripts/core-ownership-bench-lib.sh"

cat > "$fixture/expected-schedule.tsv" <<'EOF'
baseline	1
candidate	1
candidate	2
baseline	2
baseline	3
candidate	3
candidate	4
baseline	4
baseline	5
candidate	5
EOF
core_ownership_schedule 5 > "$fixture/actual-schedule.tsv"
cmp -s "$fixture/expected-schedule.tsv" "$fixture/actual-schedule.tsv" || {
  printf 'SELFTEST FAIL: release samples are not interleaved\n' >&2
  exit 1
}

core_ownership_validate_release_runs 5
if core_ownership_validate_release_runs 1 2>/dev/null; then
  printf 'SELFTEST FAIL: release profile accepted fewer than five samples\n' >&2
  exit 1
fi

mkdir -p "$fixture/runner-repo"
git -C "$fixture/runner-repo" init -q
git -C "$fixture/runner-repo" config user.email core-ownership@example.invalid
git -C "$fixture/runner-repo" config user.name core-ownership-selftest
printf 'committed\n' > "$fixture/runner-repo/runner.txt"
git -C "$fixture/runner-repo" add runner.txt
git -C "$fixture/runner-repo" commit -qm initial
runner_sha=$(git -C "$fixture/runner-repo" rev-parse HEAD)
core_ownership_validate_runner_provenance "$fixture/runner-repo" "$runner_sha"

mkdir -p "$fixture/runner-snapshot"
core_ownership_snapshot_file \
  "$fixture/runner-repo" "$runner_sha" runner.txt \
  "$fixture/runner-snapshot/runner.txt" >/dev/null
printf 'changed after snapshot\n' > "$fixture/runner-repo/runner.txt"
grep -Fx 'committed' "$fixture/runner-snapshot/runner.txt" >/dev/null || {
  printf 'SELFTEST FAIL: runner snapshot changed with the checkout\n' >&2
  exit 1
}
git -C "$fixture/runner-repo" restore runner.txt

printf 'dirty\n' >> "$fixture/runner-repo/runner.txt"
if core_ownership_validate_runner_provenance \
  "$fixture/runner-repo" "$runner_sha" 2>/dev/null; then
  printf 'SELFTEST FAIL: dirty runner checkout accepted\n' >&2
  exit 1
fi
git -C "$fixture/runner-repo" restore runner.txt
git -C "$fixture/runner-repo" commit --allow-empty -qm second
if core_ownership_validate_runner_provenance \
  "$fixture/runner-repo" "$runner_sha" 2>/dev/null; then
  printf 'SELFTEST FAIL: runner HEAD different from candidate accepted\n' >&2
  exit 1
fi

mkdir -p "$fixture/cli-repo/scripts" "$fixture/cli-repo/docs/performance"
cp "$checker" "$fixture/cli-repo/bench-check.sh"
cp "$repo_root/scripts/core-ownership-bench-profile.sh" \
  "$fixture/cli-repo/scripts/core-ownership-bench-profile.sh"
cp "$repo_root/scripts/core-ownership-bench-lib.sh" \
  "$fixture/cli-repo/scripts/core-ownership-bench-lib.sh"
cp "$repo_root/docs/performance/core-ownership-bench-policy.tsv" \
  "$fixture/cli-repo/docs/performance/core-ownership-bench-policy.tsv"
printf '# fixture\n' > "$fixture/cli-repo/README.md"
git -C "$fixture/cli-repo" init -q
git -C "$fixture/cli-repo" config user.email core-ownership@example.invalid
git -C "$fixture/cli-repo" config user.name core-ownership-selftest
git -C "$fixture/cli-repo" add .
git -C "$fixture/cli-repo" commit -qm initial
cli_sha=$(git -C "$fixture/cli-repo" rev-parse HEAD)

cat > "$fixture/cli-repo/docs/performance/core-ownership-bench-policy.tsv" <<'EOF'
# policy_version=1
# max_relative_mad_percent=5
EOF
if (cd "$fixture/cli-repo" && bash ./bench-check.sh --profile core-ownership \
  --validate) > "$fixture/cli-empty-policy.stdout" \
  2> "$fixture/cli-empty-policy.stderr"; then
  printf 'SELFTEST FAIL: public CLI accepted a policy without required benchmarks\n' >&2
  exit 1
fi
grep -F 'at least one required benchmark is required' \
  "$fixture/cli-empty-policy.stderr" >/dev/null || {
  cat "$fixture/cli-empty-policy.stderr" >&2
  exit 1
}
git -C "$fixture/cli-repo" restore docs/performance/core-ownership-bench-policy.tsv

cat > "$fixture/cli-repo/docs/performance/core-ownership-bench-policy.tsv" <<'EOF'
# policy_version=1
# max_relative_mad_percent=5
pkg::copy	5	0	required	informational	copy signal
EOF
if (cd "$fixture/cli-repo" && bash ./bench-check.sh --profile core-ownership \
  --validate) > "$fixture/cli-no-gate-policy.stdout" \
  2> "$fixture/cli-no-gate-policy.stderr"; then
  printf 'SELFTEST FAIL: public CLI accepted a policy without a required gate\n' >&2
  exit 1
fi
grep -F 'at least one required gated benchmark is required' \
  "$fixture/cli-no-gate-policy.stderr" >/dev/null || {
  cat "$fixture/cli-no-gate-policy.stderr" >&2
  exit 1
}
git -C "$fixture/cli-repo" restore docs/performance/core-ownership-bench-policy.tsv

if (cd "$fixture/cli-repo" && bash ./bench-check.sh --profile core-ownership \
  --baseline-ref "$cli_sha" --runs 1) \
  > "$fixture/cli-runs.stdout" 2> "$fixture/cli-runs.stderr"; then
  printf 'SELFTEST FAIL: public CLI accepted fewer than five samples\n' >&2
  exit 1
fi
grep -F 'requires exactly 5 samples per revision' \
  "$fixture/cli-runs.stderr" >/dev/null || {
  cat "$fixture/cli-runs.stderr" >&2
  exit 1
}

printf 'dirty\n' > "$fixture/cli-repo/untracked.txt"
if (cd "$fixture/cli-repo" && bash ./bench-check.sh --profile core-ownership \
  --baseline-ref "$cli_sha" --runs 5) \
  > "$fixture/cli-dirty.stdout" 2> "$fixture/cli-dirty.stderr"; then
  printf 'SELFTEST FAIL: public CLI accepted dirty runner checkout\n' >&2
  exit 1
fi
grep -F 'runner checkout must be clean' "$fixture/cli-dirty.stderr" >/dev/null || {
  cat "$fixture/cli-dirty.stderr" >&2
  exit 1
}
rm -f "$fixture/cli-repo/untracked.txt"

git -C "$fixture/cli-repo" commit --allow-empty -qm second
if (cd "$fixture/cli-repo" && bash ./bench-check.sh --profile core-ownership \
  --baseline-ref "$cli_sha" --candidate-ref "$cli_sha" --runs 5) \
  > "$fixture/cli-head.stdout" 2> "$fixture/cli-head.stderr"; then
  printf 'SELFTEST FAIL: public CLI accepted runner HEAD different from candidate\n' >&2
  exit 1
fi
grep -F 'does not match candidate' "$fixture/cli-head.stderr" >/dev/null || {
  cat "$fixture/cli-head.stderr" >&2
  exit 1
}

cat > "$fixture/policy.tsv" <<'EOF'
# policy_version=1
# max_relative_mad_percent=5
pkg::micro	5	50	required	gated	dual gate
pkg::parse	5	0	required	gated	parse gate
pkg::copy	5	0	required	informational	copy signal
EOF
core_ownership_validate_policy "$fixture/policy.tsv"

cat > "$fixture/missing-stability-policy.tsv" <<'EOF'
# policy_version=1
pkg::micro	5	50	required	gated	missing stability policy
EOF
if core_ownership_validate_policy \
  "$fixture/missing-stability-policy.tsv" 2>/dev/null; then
  printf 'SELFTEST FAIL: policy without a stability limit accepted\n' >&2
  exit 1
fi

cat > "$fixture/bad-policy.tsv" <<'EOF'
# policy_version=1
# max_relative_mad_percent=5
pkg::micro	five	50	required	gated	bad threshold
EOF
if core_ownership_validate_policy "$fixture/bad-policy.tsv" 2>/dev/null; then
  printf 'SELFTEST FAIL: malformed policy accepted\n' >&2
  exit 1
fi

cat > "$fixture/duplicate-policy.tsv" <<'EOF'
# policy_version=1
# max_relative_mad_percent=5
pkg::micro	5	50	required	gated	first
pkg::micro	5	50	required	gated	second
EOF
if core_ownership_validate_policy "$fixture/duplicate-policy.tsv" 2>/dev/null; then
  printf 'SELFTEST FAIL: duplicate policy accepted\n' >&2
  exit 1
fi

for run in 1 2 3 4 5; do
  cat > "$fixture/run-$run.tsv" <<EOF
pkg::copy	$((100 + run)).00
pkg::micro	$((480 + run * 10)).00
pkg::parse	$((900 + run * 10)).00
EOF
  bash "$checker" --validate-benchmark-tsv "fixture run $run" < "$fixture/run-$run.tsv"
  core_ownership_validate_required_rows "$fixture/policy.tsv" "$fixture/run-$run.tsv" "fixture run $run"
done

core_ownership_medians 5 "$fixture"/run-*.tsv > "$fixture/medians.tsv"
grep -F $'pkg::micro\t510.00' "$fixture/medians.tsv" >/dev/null
core_ownership_stability_report \
  "$fixture/policy.tsv" "$fixture"/run-*.tsv > "$fixture/stability-ok.tsv"
grep -F $'OK\tpkg::micro' "$fixture/stability-ok.tsv" >/dev/null

for run in 1 2 3 4 5; do
  cat > "$fixture/unstable-$run.tsv" <<EOF
pkg::copy	100.00
pkg::micro	500.00
pkg::parse	$((run * 1000)).00
EOF
done
if core_ownership_stability_report \
  "$fixture/policy.tsv" "$fixture"/unstable-*.tsv \
  > "$fixture/stability-bad.tsv"; then
  printf 'SELFTEST FAIL: unstable required samples accepted\n' >&2
  exit 1
fi
grep -F $'UNSTABLE\tpkg::parse' "$fixture/stability-bad.tsv" >/dev/null

observed_baseline=(9660 10040 9780 9810 10160)
observed_candidate=(10010 10040 10630 10360 10480)
for run in 1 2 3 4 5; do
  index=$((run - 1))
  cat > "$fixture/paired-baseline-$run.tsv" <<EOF
pkg::copy	100.00
pkg::micro	500.00
pkg::parse	${observed_baseline[$index]}.00
EOF
  cat > "$fixture/paired-candidate-$run.tsv" <<EOF
pkg::copy	100.00
pkg::micro	500.00
pkg::parse	${observed_candidate[$index]}.00
EOF
  core_ownership_pair_samples \
    "$fixture/paired-baseline-$run.tsv" \
    "$fixture/paired-candidate-$run.tsv" \
    > "$fixture/pair-$run.tsv"
done
core_ownership_medians 5 "$fixture"/paired-baseline-*.tsv \
  > "$fixture/paired-baseline-medians.tsv"
core_ownership_medians 5 "$fixture"/paired-candidate-*.tsv \
  > "$fixture/paired-candidate-medians.tsv"
core_ownership_paired_medians 5 "$fixture"/pair-*.tsv \
  > "$fixture/paired-medians.tsv"
grep -F $'pkg::parse\t350.00\t3.62' "$fixture/paired-medians.tsv" >/dev/null
core_ownership_compare_paired \
  "$fixture/policy.tsv" \
  "$fixture/paired-baseline-medians.tsv" \
  "$fixture/paired-candidate-medians.tsv" \
  "$fixture/paired-medians.tsv" > "$fixture/paired-comparison.tsv"
grep -F $'OK\tpkg::parse' "$fixture/paired-comparison.tsv" >/dev/null

if core_ownership_medians 5 "$fixture"/run-{1,2,3,4}.tsv >/dev/null 2>&1; then
  printf 'SELFTEST FAIL: incomplete sample set accepted\n' >&2
  exit 1
fi

cat > "$fixture/missing.tsv" <<'EOF'
pkg::copy	100.00
pkg::micro	500.00
EOF
if core_ownership_validate_required_rows "$fixture/policy.tsv" "$fixture/missing.tsv" missing 2>/dev/null; then
  printf 'SELFTEST FAIL: missing required row accepted\n' >&2
  exit 1
fi

cat > "$fixture/duplicate.tsv" <<'EOF'
pkg::micro	500.00
pkg::micro	500.00
EOF
if bash "$checker" --validate-benchmark-tsv duplicate < "$fixture/duplicate.tsv" 2>/dev/null; then
  printf 'SELFTEST FAIL: duplicate sample row accepted\n' >&2
  exit 1
fi

cat > "$fixture/baseline.tsv" <<'EOF'
pkg::copy	100.00
pkg::micro	500.00
pkg::parse	1000.00
EOF
cat > "$fixture/within-absolute.tsv" <<'EOF'
pkg::copy	200.00
pkg::micro	540.00
pkg::parse	1040.00
EOF
cat > "$fixture/within-absolute-paired.tsv" <<'EOF'
pkg::copy	100.00	100.00
pkg::micro	40.00	8.00
pkg::parse	40.00	4.00
EOF
core_ownership_compare_paired "$fixture/policy.tsv" \
  "$fixture/baseline.tsv" "$fixture/within-absolute.tsv" \
  "$fixture/within-absolute-paired.tsv" > "$fixture/comparison-ok.tsv"
grep -F $'OK\tpkg::micro' "$fixture/comparison-ok.tsv" >/dev/null
grep -F $'INFO\tpkg::copy' "$fixture/comparison-ok.tsv" >/dev/null

cat > "$fixture/regression.tsv" <<'EOF'
pkg::copy	200.00
pkg::micro	560.00
pkg::parse	1060.00
EOF
cat > "$fixture/regression-paired.tsv" <<'EOF'
pkg::copy	100.00	100.00
pkg::micro	60.00	12.00
pkg::parse	60.00	6.00
EOF
if core_ownership_compare_paired "$fixture/policy.tsv" \
  "$fixture/baseline.tsv" "$fixture/regression.tsv" \
  "$fixture/regression-paired.tsv" > "$fixture/comparison-bad.tsv"; then
  printf 'SELFTEST FAIL: gated regression accepted\n' >&2
  exit 1
fi
grep -F $'REGRESSION\tpkg::micro' "$fixture/comparison-bad.tsv" >/dev/null
grep -F $'REGRESSION\tpkg::parse' "$fixture/comparison-bad.tsv" >/dev/null

cat > "$fixture/environment-a.tsv" <<'EOF'
moon	moon-a
target	wasm-gc
EOF
cp "$fixture/environment-a.tsv" "$fixture/environment-b.tsv"
core_ownership_environment_matches "$fixture/environment-a.tsv" "$fixture/environment-b.tsv"
printf 'power\tchanged\n' >> "$fixture/environment-b.tsv"
if core_ownership_environment_matches "$fixture/environment-a.tsv" "$fixture/environment-b.tsv"; then
  printf 'SELFTEST FAIL: environment mismatch accepted\n' >&2
  exit 1
fi

cat > "$fixture/raw-ok.txt" <<'EOF'
[pkg] bench file.mbt:1 ("nanoseconds") ok
time (mean ± σ)         range (min … max)
 500 ns ± 1 ns 499 ns … 501 ns in 10 × 10 runs
[pkg] bench file.mbt:2 ("microseconds") ok
time (mean ± σ)         range (min … max)
 0.75 µs ± 1 ns 0.74 µs … 0.76 µs in 10 × 10 runs
EOF
bash "$checker" --parse-bench-output < "$fixture/raw-ok.txt" > "$fixture/parsed.tsv"
grep -F $'nanoseconds\t500.00' "$fixture/parsed.tsv" >/dev/null
grep -F $'microseconds\t750.00' "$fixture/parsed.tsv" >/dev/null

cat > "$fixture/raw-bad.txt" <<'EOF'
[pkg] bench file.mbt:1 ("bad") ok
 1 bananas
EOF
if bash "$checker" --parse-bench-output < "$fixture/raw-bad.txt" >/dev/null 2>&1; then
  printf 'SELFTEST FAIL: unknown benchmark unit accepted\n' >&2
  exit 1
fi

printf 'CORE OWNERSHIP SELFTEST PASS\n'
