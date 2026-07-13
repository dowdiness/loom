# Benchmark Detector Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `bench-check.sh` fail closed on verifier/inventory errors while suppressing alerts for explicitly classified high-variance benchmark rows.

**Architecture:** Keep the existing Bash detector as the single comparison source. Add a versioned TSV policy with default-gated rows, validation before comparison, and an `INFO` report status for informational rows. Exercise the script end to end with a fake `moon` command and temporary fixtures, then wire that self-test into pull-request CI.

**Tech Stack:** Bash, POSIX utilities already used by the repository, AWK, GitHub Actions.

## Global Constraints

- Keep default paths `docs/performance/bench-baseline.tsv` and `examples/lambda`.
- Keep the relative regression threshold at 15%; do not add an ungrounded absolute nanosecond floor.
- `REGRESSION` and `MISSING` fail; `NEW` and `INFO` do not fail.
- Parse failure, empty output, malformed TSV, duplicate keys, missing policy, invalid policy modes, and stale policy keys produce no comparison report and signal `infra`.
- `--update` must validate prospective output and policy membership before atomic baseline replacement.
- Self-tests must not invoke MoonBit or the real benchmark suite.
- Use `rtk` for shell commands and run focused checks only; skip formatters, linters, and project-wide suites.

---

### Task 1: Add the failing detector self-test

**Files:**
- Create: `scripts/bench-check-selftest.sh`

**Interfaces:**
- Consumes: `bench-check.sh` environment seams `BENCH_BASELINE`, `BENCH_MODULE_DIR`, `BENCH_POLICY`, and `BENCH_REPORT_TSV`.
- Produces: executable self-test that exits nonzero when any expected detector contract is violated.

- [ ] **Step 1: Create temporary fixture helpers and assertions**

Create a Bash self-test with `set -euo pipefail`, a temporary directory/trap, a fake module directory, and a fake `moon` executable that prints the fixture selected by `BENCH_FIXTURE` and optionally exits with `BENCH_MOON_EXIT`. Use shell substring assertions rather than external content-search commands:

```bash
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
  shift 2
  : > "$report"
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
  [[ ! -s "$report" ]] || {
    printf 'SELFTEST FAIL: unexpected comparison report\n'
    cat "$report"
    exit 1
  }
}
```

- [ ] **Step 2: Add policy and benchmark fixtures for all behavior cases**

Use three baseline rows and one informational policy row:

```bash
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
```

- [ ] **Step 3: Add assertions for status routing and verifier failures**

Append cases for matching, gated regression, missing, new, mixed, empty output, and unknown units:

```bash

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
```

- [ ] **Step 4: Add fail-closed metadata cases**

Add fixtures/cases proving stale policy and duplicate keys fail without a report:

```bash
cat > "$fixture/stale-policy" <<'EOF'
# policy_version=1
removed row	informational	stale metadata
EOF
cp "$policy" "$fixture/policy.good"
cp "$fixture/stale-policy" "$policy"
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

printf 'SELFTEST PASS\n'
```

- [ ] **Step 5: Run the new test before implementation**

Run:

```bash
rtk bash scripts/bench-check-selftest.sh
```

Expected: FAIL because `bench-check.sh` does not yet accept the fixture environment, informational policy, or fail-closed validation. Do not weaken the test to make this first run pass.

- [ ] **Step 6: Commit the failing test**

```bash
rtk git add scripts/bench-check-selftest.sh
rtk git commit -m "test(#644): specify benchmark detector policy"
```

---

### Task 2: Implement parser, validation, and eligibility policy

**Files:**
- Modify: `bench-check.sh:12-178`
- Create: `docs/performance/bench-detector-policy.tsv`

**Interfaces:**
- Consumes: the fixture environment variables and real benchmark output.
- Produces: validated `OK`, `REGRESSION`, `INFO`, `NEW`, and `MISSING` report rows; exit codes matching Task 1.

- [ ] **Step 1: Add configurable paths and policy data**

Replace fixed path assignments with default-preserving seams:

```bash
BASELINE="${BENCH_BASELINE:-docs/performance/bench-baseline.tsv}"
POLICY_FILE="${BENCH_POLICY:-docs/performance/bench-detector-policy.tsv}"
THRESHOLD=15
MODULE_DIR="${BENCH_MODULE_DIR:-examples/lambda}"
```

Create the initial policy with only the classified high-variance rows. Keep reasons short and reviewable; all omitted rows remain gated:

```tsv
# policy_version=1
baseline: reactive create-dispose cycle (existing free list) informational high-variance lifecycle benchmark
layer1: input create-dispose cycle (free list) informational high-variance lifecycle benchmark
layer2: scope create and dispose (empty) informational high-variance empty-scope benchmark
fixpoint: one iteration, single fact delta (identity rule) informational high-variance single-delta benchmark
bench: node_count hand-written informational unclassifiable measurement
bench: node_count via closure transform_fold informational unclassifiable measurement
```

- [ ] **Step 2: Make unit parse errors observable and preserve zero-row detection**

In `parse_bench_output`, track an AWK `bad` flag when a unit is not recognized and `exit 1` in `END` if any bad unit occurred. In both update and check modes, capture parsing through an `if ! parsed=$(...); then ... fi` guard so parse errors print an infra message and exit before writing or comparing.

- [ ] **Step 3: Add TSV and policy validators**

Add functions before update/check mode:

```bash
validate_benchmark_tsv() {
  local label="$1" data="$2"
  printf '%s\n' "$data" | awk -F '\t' -v label="$label" '
    NF != 2 || $1 == "" || $2 !~ /^[0-9]+(\.[0-9]+)?$/ {
      printf "%s: malformed row: %s\n", label, $0 > "/dev/stderr"
      bad = 1
      next
    }
    seen[$1]++ {
      printf "%s: duplicate benchmark: %s\n", label, $1 > "/dev/stderr"
      bad = 1
    }
    END { exit bad }
  '
}

validate_policy() {
  local prospective_baseline="$1"
  awk -F '\t' -v baseline="$prospective_baseline" '
    BEGIN {
      while ((getline line < baseline) > 0) {
        split(line, fields, "\t")
        if (fields[1] != "") baseline_name[fields[1]] = 1
      }
      close(baseline)
    }
    /^[[:space:]]*#/ || NF == 0 { next }
    NF != 3 || ($2 != "gated" && $2 != "informational") {
      print "policy: malformed row or mode: " $0 > "/dev/stderr"
      bad = 1
      next
    }
    seen[$1]++ {
      print "policy: duplicate benchmark: " $1 > "/dev/stderr"
      bad = 1
    }
    !($1 in baseline_name) {
      print "policy: stale benchmark: " $1 > "/dev/stderr"
      bad = 1
    }
    END { exit bad }
  ' "$POLICY_FILE"
}
```

The implementation may factor these validators differently, but must retain the exact fail-closed behavior and diagnostics needed by the self-test.

- [ ] **Step 4: Validate current output before comparison and report creation**

After parsing in check mode:

```bash
if ! current_tsv=$(printf '%s\n' "$raw" | parse_bench_output); then
  fail "Benchmark output parsing failed — verifier infrastructure error"
  exit 1
fi
if [[ -z "$current_tsv" ]]; then
  fail "Parsed 0 benchmarks — refusing to compare (verifier infrastructure error)"
  exit 1
fi
if ! validate_benchmark_tsv current "$current_tsv"; then
  fail "Current benchmark TSV validation failed — verifier infrastructure error"
  exit 1
fi
if ! validate_benchmark_tsv baseline "$(cat "$BASELINE")"; then
  fail "Baseline TSV validation failed — verifier infrastructure error"
  exit 1
fi
if [[ ! -f "$POLICY_FILE" ]] || ! validate_policy "$BASELINE"; then
  fail "Detector policy validation failed — verifier infrastructure error"
  exit 1
fi
```

Do not create `BENCH_REPORT_TSV` until every validation has passed.

- [ ] **Step 5: Apply policy mode in AWK comparison**

Load policy modes in the comparison AWK `BEGIN` block. For an existing row over threshold, emit `INFO` instead of `REGRESSION` when its mode is `informational`; retain baseline/current values and percentage in the report. Continue emitting `MISSING` for every baseline key not seen, independent of policy mode. Add an `informational_count` shell counter and display INFO with the existing cyan `info` helper.

The final failure condition remains:

```bash
if [[ "$regressions" -gt 0 || "$missing_count" -gt 0 ]]; then
  exit 1
fi
```

- [ ] **Step 6: Make `--update` prospective and atomic**

Parse to a temporary TSV in the same directory as the target baseline. Reject parse failure, zero rows, malformed/duplicate rows, and the existing 75% lower-count guard. Validate the policy against the staged TSV before replacing the baseline; then `mv` the staged file into place. Remove the temp file through a trap on every failure path. This prevents `--update` from creating a baseline that the next check rejects for stale policy metadata.

- [ ] **Step 7: Run the focused self-test**

Run:

```bash
rtk bash scripts/bench-check-selftest.sh
```

Expected: `SELFTEST PASS`.

- [ ] **Step 8: Commit the implementation**

```bash
rtk git add bench-check.sh docs/performance/bench-detector-policy.tsv
rtk git commit -m "ci(#644): make benchmark detector policy explicit"
```

---

### Task 3: Wire the self-test into pull-request CI and update benchmark docs

**Files:**
- Modify: `.github/workflows/ci.yml` near `dep-check`
- Modify: `BENCHMARKS.md` in the detector usage/policy section

**Interfaces:**
- Consumes: `scripts/bench-check-selftest.sh` from Task 1.
- Produces: ordinary PR CI coverage and contributor-facing policy documentation.

- [ ] **Step 1: Add a dedicated fast CI job**

Add a job after `dep-check` that checks out the repository and runs:

```yaml
  bench-detector-selftest:
    name: Benchmark Detector Self-Test
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Checkout
        uses: actions/checkout@v5
      - name: Detector policy self-test
        run: bash scripts/bench-check-selftest.sh
```

This job must not install MoonBit or run `moon bench`.

- [ ] **Step 2: Document policy routing**

In `BENCHMARKS.md`, document that:

- rows are gated by default;
- `docs/performance/bench-detector-policy.tsv` contains reviewed informational exceptions;
- `REGRESSION` and `MISSING` fail, `NEW` and `INFO` do not;
- empty/invalid output is infrastructure failure and not a benchmark inventory result;
- policy changes require a reason and self-test coverage.

- [ ] **Step 3: Run the self-test and YAML sanity check**

Run:

```bash
rtk bash scripts/bench-check-selftest.sh
rtk python3 - <<'PY'
import pathlib
text = pathlib.Path('.github/workflows/ci.yml').read_text()
assert 'bench-detector-selftest:' in text
assert 'bash scripts/bench-check-selftest.sh' in text
print('CI detector wiring ok')
PY
```

Expected: `SELFTEST PASS` and `CI detector wiring ok`.

- [ ] **Step 4: Commit CI and documentation**

```bash
rtk git add .github/workflows/ci.yml BENCHMARKS.md
rtk git commit -m "docs(ci): document benchmark detector policy"
```

---

### Task 4: Final verification and decision record

**Files:**
- Create: `docs/decisions/2026-07-13-benchmark-detector-policy.md`
- Modify: `docs/README.md` to index the ADR
- Modify: `docs/superpowers/plans/2026-07-13-benchmark-detector-policy.md` to mark complete

- [ ] **Step 1: Run focused verification**

Run:

```bash
rtk bash scripts/bench-check-selftest.sh
rtk bash -n bench-check.sh
rtk bash -n scripts/bench-check-selftest.sh
rtk python3 - <<'PY'
import pathlib
policy = pathlib.Path('docs/performance/bench-detector-policy.tsv')
rows = [line for line in policy.read_text().splitlines() if line and not line.startswith('#')]
assert rows and all(len(row.split('\t')) == 3 for row in rows)
print(f'policy rows: {len(rows)}')
PY
```

Expected: all commands succeed, including `SELFTEST PASS`.

- [ ] **Step 2: Write the ADR after implementation is verified**

Create an accepted ADR recording that benchmark detector eligibility is an explicit versioned policy, that informational rows do not alert, and that inventory/verifier failures remain fail-closed. Link the implementation spec and plan. Add the ADR to `docs/README.md`.

- [ ] **Step 3: Mark the plan complete and record closure**

Set `**Status:** Complete`, add the issue/commit links, and add:

```md
Decision record:

- ADR: [2026-07-13 benchmark detector policy](../decisions/2026-07-13-benchmark-detector-policy.md)
```

The plan is not archived in this task because it remains the active implementation record; archive only after the PR/issue closure workflow is complete.

- [ ] **Step 4: Commit closure documentation**

```bash
rtk git add docs/decisions/2026-07-13-benchmark-detector-policy.md docs/README.md docs/superpowers/plans/2026-07-13-benchmark-detector-policy.md
rtk git commit -m "docs(#644): record detector policy decision"
```
