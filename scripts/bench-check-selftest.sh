#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
checker="$repo_root/bench-check.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/module" "$fixture/bin"
cat > "$fixture/bin/moon" <<'MOON'
#!/usr/bin/env bash
cat "${BENCH_FIXTURE:?}"
exit "${BENCH_MOON_EXIT:-0}"
MOON
chmod +x "$fixture/bin/moon"

baseline="$fixture/baseline.tsv"
policy="$fixture/policy.tsv"
report="$fixture/report.tsv"
run_case() {
  local fixture_file="$1" expected_exit="$2"
  rm -f "$report"
  set +e
  BENCH_BASELINE="$baseline" BENCH_POLICY="$policy" \
    BENCH_MODULE_DIR="$fixture/module" BENCH_REPORT_TSV="$report" \
    BENCH_FIXTURE="$fixture_file" PATH="$fixture/bin:$PATH" \
    bash "$checker" > "$fixture/stdout" 2> "$fixture/stderr"
  actual=$?
  set -e
  [[ "$actual" -eq "$expected_exit" ]] || {
    printf 'SELFTEST FAIL: expected exit %s, got %s\n' "$expected_exit" "$actual"
    cat "$fixture/stdout" "$fixture/stderr"
    exit 1
  }
}
run_update_case() {
  local fixture_file="$1" expected_exit="$2"
  set +e
  BENCH_BASELINE="$baseline" BENCH_POLICY="$policy" \
    BENCH_MODULE_DIR="$fixture/module" BENCH_FIXTURE="$fixture_file" \
    PATH="$fixture/bin:$PATH" bash "$checker" --update \
    > "$fixture/stdout" 2> "$fixture/stderr"
  actual=$?
  set -e
  [[ "$actual" -eq "$expected_exit" ]] || {
    printf 'SELFTEST FAIL: update expected exit %s, got %s\n' "$expected_exit" "$actual"
    cat "$fixture/stdout" "$fixture/stderr"
    exit 1
  }
}
assert_output_contains() {
  local needle="$1"
  [[ "$(cat "$fixture/stdout")" == *"$needle"* ]] || {
    printf 'SELFTEST FAIL: output missing %s\n' "$needle"
    exit 1
  }
}
assert_report_contains() {
  local needle="$1"
  [[ -f "$report" && "$(cat "$report")" == *"$needle"* ]] || {
    printf 'SELFTEST FAIL: report missing %s\n' "$needle"
    exit 1
  }
}
assert_no_report() {
  [[ ! -e "$report" ]] || {
    printf 'SELFTEST FAIL: unexpected comparison report\n'
    cat "$report"
    exit 1
  }
}

cat > "$baseline" <<'EOF'
gated row	100.00
noisy row	100.00
missing row	100.00
EOF
cat > "$policy" <<'EOF'
# policy_version=1
noisy row	informational	known high variance fixture
EOF
cat > "$fixture/ok" <<'EOF'
[bench] ("gated row") ok
  100 ns
[bench] ("noisy row") ok
  100 ns
[bench] ("missing row") ok
  100 ns
EOF
cat > "$fixture/regression" <<'EOF'
[bench] ("gated row") ok
  150 ns
[bench] ("noisy row") ok
  150 ns
[bench] ("missing row") ok
  100 ns
EOF
cat > "$fixture/missing" <<'EOF'
[bench] ("gated row") ok
  100 ns
[bench] ("noisy row") ok
  100 ns
EOF
cat > "$fixture/new" <<'EOF'
[bench] ("gated row") ok
  100 ns
[bench] ("noisy row") ok
  100 ns
[bench] ("missing row") ok
  100 ns
[bench] ("new row") ok
  100 ns
EOF
cat > "$fixture/mixed" <<'EOF'
[bench] ("gated row") ok
  150 ns
[bench] ("noisy row") ok
  150 ns
[bench] ("new row") ok
  100 ns
EOF
cat > "$fixture/unknown-unit" <<'EOF'
[bench] ("gated row") ok
  100 ns
[bench] ("noisy row") ok
  100 bananas
EOF

run_case "$fixture/ok" 0
assert_output_contains 'OK: 3'
assert_report_contains $'OK	gated row'

run_case "$fixture/regression" 1
assert_output_contains 'INFO  noisy row'
assert_output_contains '1 regression(s) exceed 15% threshold.'
assert_report_contains $'REGRESSION	gated row'
assert_report_contains $'INFO	noisy row'

run_case "$fixture/missing" 1
assert_output_contains 'MISSING  missing row'
assert_report_contains $'MISSING	missing row'

run_case "$fixture/new" 0
assert_output_contains 'NEW  new row'
assert_output_contains 'No regressions.'

run_case "$fixture/mixed" 1
assert_report_contains $'REGRESSION	gated row'
assert_report_contains $'INFO	noisy row'
assert_report_contains $'NEW	new row'
assert_report_contains $'MISSING	missing row'

: > "$fixture/empty"
run_case "$fixture/empty" 1
assert_no_report

run_case "$fixture/unknown-unit" 1
assert_no_report

cat > "$fixture/stale-policy" <<'EOF'
# policy_version=1
removed row	informational	stale metadata
EOF
cp "$policy" "$fixture/policy.good"
cp "$fixture/stale-policy" "$policy"
run_case "$fixture/ok" 1
assert_no_report
cp "$fixture/policy.good" "$policy"
printf 'noisy row	informational	missing version\n' > "$policy"
run_case "$fixture/ok" 1
assert_no_report

printf '# policy_version=999\nnoisy row	informational	wrong version\n' > "$policy"
run_case "$fixture/ok" 1
assert_no_report

cp "$fixture/policy.good" "$policy"


cat > "$fixture/duplicate-current" <<'EOF'
[bench] ("gated row") ok
  100 ns
[bench] ("gated row") ok
  100 ns
[bench] ("noisy row") ok
  100 ns
EOF
run_case "$fixture/duplicate-current" 1
assert_no_report

cp "$baseline" "$fixture/baseline.good"
cat > "$baseline" <<'EOF'
gated row	100.00
gated row	100.00
noisy row	100.00
missing row	100.00
EOF
run_case "$fixture/ok" 1
assert_no_report
cp "$fixture/baseline.good" "$baseline"
cp "$baseline" "$fixture/baseline.before-update"
cat > "$policy" <<'EOF'
# policy_version=1
removed row	informational	stale metadata
EOF
run_update_case "$fixture/ok" 1
cmp -s "$fixture/baseline.before-update" "$baseline" || {
  printf 'SELFTEST FAIL: stale update changed baseline\n'
  exit 1
}
cp "$fixture/policy.good" "$policy"
run_update_case "$fixture/new" 0
cat > "$fixture/expected-updated" <<'EOF'
gated row	100.00
noisy row	100.00
missing row	100.00
new row	100.00
EOF
cmp -s "$fixture/expected-updated" "$baseline" || {
  printf 'SELFTEST FAIL: valid update did not replace baseline correctly\n'
  exit 1
}


printf 'SELFTEST PASS\n'
