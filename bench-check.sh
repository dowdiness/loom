#!/usr/bin/env bash
# bench-check.sh — detect benchmark regressions vs saved baseline
#
# Usage:
#   bash bench-check.sh            # compare current run against baseline (exit 1 on regression)
#   bash bench-check.sh --update   # run benchmarks and save new baseline
#
# Run from repo root (where README.md lives).

set -euo pipefail

BASELINE="docs/performance/bench-baseline.tsv"
THRESHOLD=15   # % regression that triggers failure
MODULE_DIR="examples/lambda"

# --- colour helpers (same style as check-docs.sh) ---
ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m⚠\033[0m %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*"; }
info() { printf "  \033[36m·\033[0m %s\n" "$*"; }

# --- guard: must run from repo root ---
if [[ ! -f "README.md" || ! -d "docs" ]]; then
  echo "Run from repo root (where README.md and docs/ live)."
  exit 1
fi

# --- parse_bench_output: stdin → TSV (name <TAB> mean_ns) ---
# Handles units: ns, µs, ms
parse_bench_output() {
  awk '
    /\) ok$/ {
      # Extract quoted name from: [module] bench file.mbt:N ("name") ok
      s = $0
      sub(/.*\("/, "", s)
      sub(/"\).*/, "", s)
      pending_name = s
    }
    pending_name != "" && /^[[:space:]]+[0-9]/ {
      val  = $1
      unit = $2
      # Normalise to nanoseconds.
      # Units seen in practice: ns, µs (multi-byte), ms, s.
      # Detect ns/ms/s by their ASCII content; µs is the only remaining unit
      # ending with "s" — matched via substr(unit, length(unit), 1) so the
      # comparison is pure ASCII and works in both C and UTF-8 locales.
      if (substr(unit, 1, 1) == "n") mult = 1              # ns
      else if (substr(unit, 1, 1) == "m") mult = 1000000   # ms
      else if (unit == "s")            mult = 1000000000   # s  (must precede trailing-s check)
      else if (substr(unit, length(unit), 1) == "s") mult = 1000  # µs
      else {
        print "unrecognised unit: " unit > "/dev/stderr"
        pending_name = ""
        next
      }
      printf "%s\t%.2f\n", pending_name, val * mult
      pending_name = ""
    }
  '
}

# --- --update mode: run benchmarks and write baseline ---
if [[ "${1:-}" == "--update" ]]; then
  echo "Benchmark baseline update"
  echo "-------------------------"
  info "Running: cd $MODULE_DIR && moon bench --release"
  raw=$(cd "$MODULE_DIR" && moon bench --release 2>&1)
  parsed=$(echo "$raw" | parse_bench_output)
  count=$(wc -l <<< "$parsed")
  [[ -z "$parsed" ]] && count=0
  if [[ "$count" -eq 0 ]]; then
    fail "Parsed 0 benchmarks — refusing to overwrite baseline (parse failure?)"
    exit 1
  fi
  if [[ -f "$BASELINE" ]]; then
    baseline_count=$(wc -l < "$BASELINE")
    if [[ "$count" -lt $((baseline_count * 3 / 4)) ]]; then
      fail "Parsed only $count benchmarks vs $baseline_count in baseline — refusing to update"
      fail "If benchmarks were intentionally removed, delete the baseline and re-run."
      exit 1
    fi
  fi
  echo "$parsed" > "$BASELINE"
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

echo "Benchmark regression check (threshold: ${THRESHOLD}%)"
echo "------------------------------------------------------"
info "Running: cd $MODULE_DIR && moon bench --release"
raw=$(cd "$MODULE_DIR" && moon bench --release 2>&1)
current_tsv=$(echo "$raw" | parse_bench_output)

# Compare baseline vs current using awk
results=$(awk -F'\t' \
  -v threshold="$THRESHOLD" \
  'NR == FNR { baseline[$1] = $2; next }
   {
     name = $1; cur = $2
     seen[name] = 1
     if (name in baseline) {
       ref = baseline[name]
       if (ref > 0) pct = (cur - ref) / ref * 100
       else         pct = 0
       if (pct > threshold)
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
  "$BASELINE" <(echo "$current_tsv"))

regressions=0
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
    NEW)
      warn "NEW  $f1  (${f2} ns — not in baseline)"
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
echo "  OK: $ok_count   NEW: $new_count   MISSING: $missing_count   REGRESSIONS: $regressions"
echo ""

if [[ "$regressions" -gt 0 || "$missing_count" -gt 0 ]]; then
  [[ "$regressions" -gt 0 ]] && printf "\033[31m%d regression(s) exceed ${THRESHOLD}%% threshold.\033[0m\n" "$regressions"
  [[ "$missing_count" -gt 0 ]] && printf "\033[31m%d benchmark(s) missing from current run.\033[0m\n" "$missing_count"
  printf "Run with --update to accept new baseline.\n"
  exit 1
else
  printf "\033[32mNo regressions.\033[0m\n"
fi
