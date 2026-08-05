#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
checker="$repo_root/bench-check.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

# shellcheck source=core-ownership-bench-lib.sh
source "$repo_root/scripts/core-ownership-bench-lib.sh"

cat > "$fixture/policy.tsv" <<'EOF'
# policy_version=1
pkg::micro	5	50	required	gated	dual gate
pkg::parse	5	0	required	gated	parse gate
pkg::copy	5	0	required	informational	copy signal
EOF
core_ownership_validate_policy "$fixture/policy.tsv"

cat > "$fixture/bad-policy.tsv" <<'EOF'
# policy_version=1
pkg::micro	five	50	required	gated	bad threshold
EOF
if core_ownership_validate_policy "$fixture/bad-policy.tsv" 2>/dev/null; then
  printf 'SELFTEST FAIL: malformed policy accepted\n' >&2
  exit 1
fi

cat > "$fixture/duplicate-policy.tsv" <<'EOF'
# policy_version=1
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
core_ownership_compare_medians "$fixture/policy.tsv" \
  "$fixture/baseline.tsv" "$fixture/within-absolute.tsv" > "$fixture/comparison-ok.tsv"
grep -F $'OK\tpkg::micro' "$fixture/comparison-ok.tsv" >/dev/null
grep -F $'INFO\tpkg::copy' "$fixture/comparison-ok.tsv" >/dev/null

cat > "$fixture/regression.tsv" <<'EOF'
pkg::copy	200.00
pkg::micro	560.00
pkg::parse	1060.00
EOF
if core_ownership_compare_medians "$fixture/policy.tsv" \
  "$fixture/baseline.tsv" "$fixture/regression.tsv" > "$fixture/comparison-bad.tsv"; then
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
