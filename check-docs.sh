#!/usr/bin/env bash
# check-docs.sh — validate docs hierarchy rules
# Run from repo root: bash check-docs.sh

set -euo pipefail

errors=0
warnings=0

ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn() { printf "  \033[33m⚠\033[0m %s\n" "$*"; warnings=$((warnings + 1)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*"; errors=$((errors + 1)); }

# Must run from repo root
if [[ ! -f "README.md" || ! -d "docs" ]]; then
  echo "Run from repo root (where README.md and docs/ live)."
  exit 1
fi

echo "Docs health check"
echo "-----------------"

# 1. Line limits
echo ""
echo "Line limits:"
readme_lines=$(wc -l < README.md)
roadmap_lines=$(wc -l < ROADMAP.md)

[[ "$readme_lines" -le 60 ]] \
  && ok "README.md: $readme_lines lines (≤60)" \
  || fail "README.md: $readme_lines lines (limit: 60)"

[[ "$roadmap_lines" -le 450 ]] \
  && ok "ROADMAP.md: $roadmap_lines lines (≤450)" \
  || fail "ROADMAP.md: $roadmap_lines lines (limit: 450)"

# 2. Completed plans still in docs/plans/
echo ""
echo "Completed plans in docs/plans/:"
found=0
shopt -s nullglob
for f in docs/plans/*.md; do
  if grep -qiE "^\*\*Status:\*\*\s*Complete|^Status:\s*(Complete|Done)" "$f"; then
    warn "$f — move to docs/archive/completed-phases/"
    found=1
  fi
done
shopt -u nullglob
[[ "$found" -eq 0 ]] && ok "None found"

# 3. Non-archive docs/ files linked from docs/README.md
echo ""
echo "Navigation index coverage (docs/ excluding archive):"
any_missing=0
while IFS= read -r -d '' f; do
  rel="${f#docs/}"
  if grep -qF "$rel" docs/README.md; then
    ok "$rel"
  else
    warn "$rel — not linked from docs/README.md"
    any_missing=1
  fi
done < <(find docs \
  -name "*.md" \
  ! -name "README.md" \
  ! -path "docs/archive/*" \
  -print0 | sort -z)
[[ "$any_missing" -eq 0 ]] || true  # warnings already counted above

# 4. Fossil references in current docs
#
# Deleted/renamed public API names that must not appear in *current* docs.
# Historical material (docs/archive, ADRs, ROADMAP completed-work sections,
# benchmark_history) is excluded by path — it legitimately cites history.
#
# When a public package/function is renamed or removed, add its old name to
# `fossils` below in the same commit as the rename.
echo ""
echo "Fossil references in current docs:"
fossils=(
  "@bridge."             # bridge package removed 2026-03-04 (seam trait cleanup)
  "new_reactive_parser"  # removed 2026-04-17 (unified Parser[Ast])
  "@ast.AstNode"         # type removed 2026-03-05 (lambda AstNode removal)
)
fossil_hits=0
while IFS= read -r -d '' f; do
  for pat in "${fossils[@]}"; do
    if grep -qF -- "$pat" "$f"; then
      fail "$f contains fossil '$pat'"
      fossil_hits=1
    fi
  done
done < <(find . -name "*.md" \
  ! -path "*/_build/*" \
  ! -path "./docs/archive/*" \
  ! -path "./docs/decisions/*" \
  ! -path "./docs/performance/benchmark_history.md" \
  ! -name "ROADMAP.md" \
  -print0 | sort -z)
[[ "$fossil_hits" -eq 0 ]] && ok "No fossil references found"

# Summary
echo ""
echo "-----------------"
if   [[ "$errors" -eq 0 && "$warnings" -eq 0 ]]; then
  printf "\033[32mAll checks passed.\033[0m\n"
elif [[ "$errors" -eq 0 ]]; then
  printf "\033[33m%d warning(s). Review above.\033[0m\n" "$warnings"
else
  printf "\033[31m%d error(s), %d warning(s).\033[0m\n" "$errors" "$warnings"
  exit 1
fi
