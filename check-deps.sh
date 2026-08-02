#!/usr/bin/env bash
# check-deps.sh — enforce loom package-dependency boundary rules
# Run from repo root: bash check-deps.sh
#
# Rules enforced:
#   1. Engine packages (core, incremental, pipeline) MUST NOT import loom/projection.
#      Prevents the layering inversion from recurring (see docs/analysis/2026-06-20-architecture-restructuring.md §5).
#   2. seam MUST NOT import dowdiness/loom.
#      Keeps the CST model usable by packages above it.
#      Note: seam importing example packages (dowdiness/json etc.) is already
#      enforced at compile time — moon resolves it as a circular dependency.
#   3. diagnostic production code MUST depend only on MoonBit core packages.
#      Keeps structured diagnostics independent from Loom and parser policy.
#   4. diagnostic-pretty production code MUST depend exactly on diagnostic,
#      pretty, and moji. Keeps the optional adapter narrow and format-neutral.

set -euo pipefail

errors=0

ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*"; errors=$((errors + 1)); }

# Must run from repo root
if [[ ! -f "README.md" || ! -d "loom" ]]; then
  echo "Run from repo root (where README.md and loom/ live)."
  exit 1
fi

echo "Dependency boundary check"
echo "-------------------------"
echo ""

# --- Rule 1: engine must not import projection ---
echo "Rule 1: engine packages must not import dowdiness/loom/projection"

ENGINE_PKGS=(
  "loom/core"
  "loom/incremental"
  "loom/pipeline"
)

for pkg in "${ENGINE_PKGS[@]}"; do
  pkg_file="$pkg/moon.pkg"
  if [[ ! -f "$pkg_file" ]]; then
    fail "$pkg_file not found — package layout changed, update this script"
    continue
  fi
  if grep -q '"dowdiness/loom/projection"' "$pkg_file"; then
    fail "$pkg_file imports dowdiness/loom/projection — this violates the engine/projection boundary rule"
  else
    ok "$pkg/moon.pkg: no projection import"
  fi
done

echo ""
echo "Rule 2: seam must not import dowdiness/loom"

# Find all moon.pkg files under seam/
SEAM_PKGS=$(find seam -name "moon.pkg" 2>/dev/null)
if [[ -z "$SEAM_PKGS" ]]; then
  fail "No moon.pkg files found under seam/ — check the path"
else
  while IFS= read -r pkg_file; do
    if grep -q '"dowdiness/loom' "$pkg_file"; then
      fail "$pkg_file imports a dowdiness/loom package — seam must not depend on loom"
    else
      ok "$pkg_file: no loom import"
    fi
  done <<< "$SEAM_PKGS"
fi

echo ""
echo "Rule 3: diagnostic production dependencies must be MoonBit core only"

if [[ ! -f "diagnostic/moon.mod" || ! -f "diagnostic/moon.pkg" ]]; then
  fail "diagnostic manifests not found — package layout changed, update this script"
else
  if grep -q '^import[[:space:]]*{' diagnostic/moon.mod; then
    fail "diagnostic/moon.mod declares module dependencies — production must use MoonBit core only"
  else
    ok "diagnostic/moon.mod: no external module dependencies"
  fi

  invalid_diagnostic_imports=$(grep -E '^[[:space:]]*"' diagnostic/moon.pkg | grep -Ev '"moonbitlang/core/' || true)
  if [[ -n "$invalid_diagnostic_imports" ]]; then
    fail "diagnostic/moon.pkg imports a non-core package: $invalid_diagnostic_imports"
  else
    ok "diagnostic/moon.pkg: package imports are MoonBit core only"
  fi

  nested_diagnostic_packages=$(find diagnostic -mindepth 2 -name moon.pkg -print)
  if [[ -n "$nested_diagnostic_packages" ]]; then
    fail "diagnostic contains an unexpected nested package: $nested_diagnostic_packages"
  else
    ok "diagnostic: no hidden nested production packages"
  fi
fi

echo ""
echo "Rule 4: diagnostic-pretty production dependencies are exactly diagnostic, pretty, and moji"

if [[ ! -f "diagnostic-pretty/moon.mod" || ! -f "diagnostic-pretty/moon.pkg" ]]; then
  fail "diagnostic-pretty manifests not found — package layout changed, update this script"
else
  expected_pretty_deps=$(printf '%s\n' \
    'dowdiness/diagnostic' \
    'dowdiness/moji' \
    'dowdiness/pretty' | sort)
  actual_pretty_mod_deps=$(grep -oE '"dowdiness/[^"@]+@' diagnostic-pretty/moon.mod | tr -d '"@' | sort)
  actual_pretty_pkg_deps=$(grep -oE '"dowdiness/[^" ]+"' diagnostic-pretty/moon.pkg | tr -d '"' | sort)
  if [[ "$actual_pretty_mod_deps" == "$expected_pretty_deps" ]]; then
    ok "diagnostic-pretty/moon.mod: exact adapter module dependencies"
  else
    fail "diagnostic-pretty/moon.mod dependencies differ from diagnostic, moji, pretty"
  fi
  if [[ "$actual_pretty_pkg_deps" == "$expected_pretty_deps" ]]; then
    ok "diagnostic-pretty/moon.pkg: exact adapter package imports"
  else
    fail "diagnostic-pretty/moon.pkg imports differ from diagnostic, moji, pretty"
  fi
fi

echo ""
echo "-------------------------"
if [[ "$errors" -gt 0 ]]; then
  echo "  $errors error(s) found."
  exit 1
else
  echo "  All dependency boundary rules pass."
fi
