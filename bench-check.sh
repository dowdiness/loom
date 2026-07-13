#!/usr/bin/env bash
# bench-check.sh — detect benchmark regressions vs saved baseline
#
# Usage:
#   bash bench-check.sh            # compare current run against baseline (exit 1 on regression)
#   bash bench-check.sh --update   # run benchmarks and save new baseline
#
# Run from repo root (where README.md lives).

set -euo pipefail

BASELINE="${BENCH_BASELINE:-docs/performance/bench-baseline.tsv}"
POLICY_FILE="${BENCH_POLICY:-docs/performance/bench-detector-policy.tsv}"
THRESHOLD=15   # % regression that triggers failure for gated rows
MODULE_DIR="${BENCH_MODULE_DIR:-examples/lambda}"
staged_baseline=""

# --- colour helpers (same style as check-docs.sh) ---
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m⚠\033[0m %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*"; }
info() { printf "  \033[36m·\033[0m %s\n" "$*"; }

cleanup_staged_baseline() {
  if [[ -n "$staged_baseline" ]]; then
    rm -f "$staged_baseline"
  fi
}
trap cleanup_staged_baseline EXIT

# --- guard: must run from repo root ---
if [[ ! -f "README.md" || ! -d "docs" ]]; then
  echo "Run from repo root (where README.md and docs/ live)."
  exit 1
fi

# --- parse_bench_output: stdin → TSV (name <TAB> mean_ns) ---
# Handles units: ns, µs, ms, s. Any unknown unit makes parsing fail.
parse_bench_output() {
  awk '
    /\) ok$/ {
      s = $0
      sub(/.*\("/, "", s)
      sub(/"\).*/, "", s)
      pending_name = s
    }
    pending_name != "" && /^[[:space:]]+[0-9]/ {
      val  = $1
      unit = $2
      if (unit == "ns")                  mult = 1          # ns
      else if (unit == "ms")             mult = 1000000   # ms
      else if (unit == "s")              mult = 1000000000 # s
      else if (unit == "µs" || unit == "us" || unit == "μs") mult = 1000
      else {
        print "unrecognised unit: " unit > "/dev/stderr"
        bad = 1
        pending_name = ""
        next
      }
      printf "%s\t%.2f\n", pending_name, val * mult
      pending_name = ""
    }
    END {
      if (bad) exit 1
    }
  '
}

# --- validate benchmark TSV shape and unique keys ---
validate_benchmark_tsv() {
  local label="$1" data="$2"
  printf '%s\n' "$data" | awk -F '\t' -v label="$label" '
    NF != 2 || $1 == "" || $2 !~ /^[0-9]+(\.[0-9]+)?$/ {
      printf "%s: malformed row: %s\n", label, $0 > "/dev/stderr"
      bad = 1
      next
    }
    {
      if ($1 in seen) {
        printf "%s: duplicate benchmark: %s\n", label, $1 > "/dev/stderr"
        bad = 1
      }
      seen[$1] = 1
    }
    END { exit bad }
  '
}

# --- validate that --update does not discard baseline benchmark names ---
validate_update_inventory() {
  local baseline_data="$1" current_data="$2"
  awk -F '\t' '
    NR == FNR {
      current[$1] = 1
      next
    }
    !($1 in current) {
      printf "update: benchmark missing from current run: %s\n", $1 > "/dev/stderr"
      bad = 1
    }
    END { exit bad }
  ' <(printf '%s\n' "$current_data") <(printf '%s\n' "$baseline_data")
}

# --- validate policy format, version, unique keys, and baseline membership ---
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
    /^[[:space:]]*#/ {
      if ($0 == "# policy_version=1") {
        version_count++
      } else if ($0 ~ /^[[:space:]]*# policy_version=/) {
        print "policy: unsupported version: " $0 > "/dev/stderr"
        bad = 1
      }
      next
    }
    NF == 0 { next }
    NF != 3 || $1 == "" || $3 !~ /[^[:space:]]/ ||
      ($2 != "gated" && $2 != "informational") {
      print "policy: malformed row or mode: " $0 > "/dev/stderr"
      bad = 1
      next
    }
    {
      if ($1 in seen) {
        print "policy: duplicate benchmark: " $1 > "/dev/stderr"
        bad = 1
      }
      seen[$1] = 1
    }
    !($1 in baseline_name) {
      print "policy: stale benchmark: " $1 > "/dev/stderr"
      bad = 1
    }
    END {
      if (version_count != 1) {
        print "policy: exactly one # policy_version=1 declaration required" > "/dev/stderr"
        bad = 1
      }
      exit bad
    }
  ' "$POLICY_FILE"
}

# --- run benchmarks once and parse output ---
run_benchmarks() {
  local raw
  if ! raw=$(cd "$MODULE_DIR" && moon bench --release 2>&1); then
    return 1
  fi
  if ! printf '%s\n' "$raw" | parse_bench_output; then
    return 1
  fi
}

# --- --validate mode: validate checked-in baseline and policy without running benchmarks ---
if [[ "${1:-}" == "--validate" ]]; then
  if [[ ! -f "$BASELINE" || ! -f "$POLICY_FILE" ]]; then
    fail "Baseline or detector policy not found — verifier infrastructure error"
    exit 1
  fi
  if ! validate_benchmark_tsv baseline "$(<"$BASELINE")"; then
    fail "Baseline TSV validation failed — verifier infrastructure error"
    exit 1
  fi
  if ! validate_policy "$BASELINE"; then
    fail "Detector policy validation failed — verifier infrastructure error"
    exit 1
  fi
  ok "Baseline and detector policy are valid"
  exit 0
fi

# --- --update mode: run benchmarks and write baseline ---
if [[ "${1:-}" == "--update" ]]; then
  echo "Benchmark baseline update"
  echo "-------------------------"
  info "Running: cd $MODULE_DIR && moon bench --release"

  if ! parsed=$(run_benchmarks); then
    fail "Benchmark output parsing failed — verifier infrastructure error"
    exit 1
  fi
  if [[ -z "$parsed" ]]; then
    fail "Parsed 0 benchmarks — refusing to overwrite baseline (parse failure?)"
    exit 1
  fi
  if ! validate_benchmark_tsv current "$parsed"; then
    fail "Current benchmark TSV validation failed — verifier infrastructure error"
    exit 1
  fi

  count=$(printf '%s\n' "$parsed" | wc -l)
  if [[ -f "$BASELINE" ]]; then
    if ! validate_benchmark_tsv baseline "$(<"$BASELINE")"; then
      fail "Baseline TSV validation failed — verifier infrastructure error"
      exit 1
    fi
    if ! validate_update_inventory "$(<"$BASELINE")" "$parsed"; then
      fail "Benchmark inventory differs from baseline — refusing to update"
      fail "Remove intentionally retired baseline rows manually, then re-run."
      exit 1
    fi
    baseline_count=$(wc -l < "$BASELINE")
    if [[ "$count" -lt $((baseline_count * 3 / 4)) ]]; then
      fail "Parsed only $count benchmarks vs $baseline_count in baseline — refusing to update"
      fail "If benchmarks were intentionally removed, delete the baseline and re-run."
      exit 1
    fi
  fi

  if [[ ! -f "$POLICY_FILE" ]]; then
    fail "Detector policy not found — verifier infrastructure error"
    exit 1
  fi
  staged_baseline=$(mktemp "${BASELINE}.tmp.XXXXXX")
  printf '%s\n' "$parsed" > "$staged_baseline"
  if ! validate_policy "$staged_baseline"; then
    fail "Detector policy validation failed for prospective baseline — verifier infrastructure error"
    exit 1
  fi
  mv "$staged_baseline" "$BASELINE"
  staged_baseline=""
  ok "Baseline saved: $BASELINE ($count benchmarks)"
  echo ""
  echo "Commit with:"
  echo "  git add $BASELINE && git commit -m 'perf: update bench baseline'"
  exit 0
fi

# --- check mode: compare current run against baseline ---
if [[ ! -f "$BASELINE" ]]; then
  echo "No baseline found at $BASELINE."
  echo "Run first:  bash bench-check.sh --update"
  exit 1
fi
if [[ ! -f "$POLICY_FILE" ]]; then
  fail "Detector policy not found — verifier infrastructure error"
  exit 1
fi

if ! validate_benchmark_tsv baseline "$(<"$BASELINE")"; then
  fail "Baseline TSV validation failed — verifier infrastructure error"
  exit 1
fi
if ! validate_policy "$BASELINE"; then
  fail "Detector policy validation failed — verifier infrastructure error"
  exit 1
fi

echo "Benchmark regression check (threshold: ${THRESHOLD}%, gated rows)"
echo "------------------------------------------------------"
info "Running: cd $MODULE_DIR && moon bench --release"
if ! current_tsv=$(run_benchmarks); then
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

# Compare baseline vs current using awk.
results=$(awk -F'\t' \
  -v threshold="$THRESHOLD" \
  -v policy_file="$POLICY_FILE" \
  'BEGIN {
     while ((getline line < policy_file) > 0) {
       if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) continue
       split(line, fields, "\t")
       policy[fields[1]] = fields[2]
     }
     close(policy_file)
   }
   NR == FNR { baseline[$1] = $2; next }
   {
     name = $1; cur = $2
     seen[name] = 1
     if (name in baseline) {
       ref = baseline[name]
       if (ref > 0) pct = (cur - ref) / ref * 100
       else         pct = 0
       mode = ((name in policy) ? policy[name] : "gated")
       if (pct > threshold && mode == "informational")
         printf "INFO\t%s\t%+.1f%%\t%.0f → %.0f ns\n", name, pct, ref, cur
       else if (pct > threshold)
         printf "REGRESSION\t%s\t%+.1f%%\t%.0f → %.0f ns\n", name, pct, ref, cur
       else
         printf "OK\t%s\t%+.1f%%\n", name, pct
     } else {
       printf "NEW\t%s\t%.0f ns\n", name, cur
     }
   }
   END {
     for (name in baseline)
       if (!(name in seen))
         printf "MISSING\t%s\n", name
   }' \
  "$BASELINE" <(printf '%s\n' "$current_tsv"))

# Machine-readable copy of the comparison (tab-separated STATUS\tname\t...)
# for CI consumers; the pretty-printed loop below stays the human interface.
if [[ -n "${BENCH_REPORT_TSV:-}" ]]; then
  printf '%s\n' "$results" > "$BENCH_REPORT_TSV"
fi

regressions=0
informational_count=0
new_count=0
ok_count=0
missing_count=0

echo ""
while IFS=$'\t' read -r status f1 f2 f3; do
  case "$status" in
    OK)
      ok "$f1  ($f2)"
      ok_count=$((ok_count + 1))
      ;;
    REGRESSION)
      fail "REGRESSION  $f1  ($f2)  [$f3]"
      regressions=$((regressions + 1))
      ;;
    INFO)
      info "INFO  $f1  ($f2)  [$f3]"
      informational_count=$((informational_count + 1))
      ;;
    NEW)
      warn "NEW  $f1  (${f2} — not in baseline)"
      new_count=$((new_count + 1))
      ;;
    MISSING)
      fail "MISSING  $f1  (in baseline, absent from current run)"
      missing_count=$((missing_count + 1))
      ;;
    *)
      warn "Unexpected result line: $status $f1 $f2 $f3"
      ;;
  esac
done <<< "$results"

echo ""
echo "------------------------------------------------------"
echo "  OK: $ok_count   INFO: $informational_count   NEW: $new_count   MISSING: $missing_count   REGRESSIONS: $regressions"
echo ""

if [[ "$regressions" -gt 0 || "$missing_count" -gt 0 ]]; then
  [[ "$regressions" -gt 0 ]] && printf "\033[31m%d regression(s) exceed ${THRESHOLD}%% threshold.\033[0m\n" "$regressions"
  [[ "$missing_count" -gt 0 ]] && printf "\033[31m%d benchmark(s) missing from current run.\033[0m\n" "$missing_count"
  printf "Run with --update to accept new baseline.\n"
  exit 1
else
  printf "\033[32mNo regressions.\033[0m\n"
fi
