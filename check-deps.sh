#!/usr/bin/env bash
# check-deps.sh — enforce loom package-dependency boundary rules
# Run from repo root: bash check-deps.sh
#
# Rules enforced:
#   1. Engine packages (core, incremental, pipeline) MUST NOT import loom/projection.
#      Prevents the layering inversion from recurring (see docs/analysis/2026-06-20-architecture-restructuring.md §5).
#   2. seam MUST NOT import dowdiness/loom or any examples/ package.
#      Keeps the CST model reusable by packages above it.

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
  "loom/src/core"
  "loom/src/incremental"
  "loom/src/pipeline"
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
echo "Rule 2: seam must not import dowdiness/loom or examples"

# Find all moon.pkg files under seam/
SEAM_PKGS=$(find seam -name "moon.pkg" 2>/dev/null)
if [[ -z "$SEAM_PKGS" ]]; then
  fail "No moon.pkg files found under seam/ — check the path"
else
  while IFS= read -r pkg_file; do
    if grep -q '"dowdiness/loom' "$pkg_file"; then
      fail "$pkg_file imports a dowdiness/loom package — seam must not depend on loom"
    elif grep -q '"dowdiness/.*examples' "$pkg_file"; then
      fail "$pkg_file imports an examples package — seam must not depend on examples"
    else
      ok "$pkg_file: no loom or examples import"
    fi
  done <<< "$SEAM_PKGS"
fi

echo ""
echo "-------------------------"
if [[ "$errors" -gt 0 ]]; then
  echo "  $errors error(s) found."
  exit 1
else
  echo "  All dependency boundary rules pass."
fi
