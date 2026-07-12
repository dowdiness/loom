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

# 4. Changed archived plans have a decision-record note
#
# Historical archived plans predate the ADR rule, so this guard only checks
# archived plans changed in the current branch/worktree. Override the comparison
# base with DOCS_BASE_REF when origin/main is not the right baseline.
echo ""
echo "Decision records for changed archived plans:"
decision_checked=0
check_archived_plan_decision_record() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  decision_checked=1
  if grep -qF "Decision record:" "$f" &&
     { grep -qF "decisions/" "$f" || grep -qF "No ADR needed:" "$f"; }; then
    ok "$f"
  else
    fail "$f — add Decision record with an ADR link or No ADR needed"
  fi
}

base_ref="${DOCS_BASE_REF:-origin/main}"
if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  while IFS= read -r -d '' f; do
    check_archived_plan_decision_record "$f"
  done < <(git diff --name-only -z --diff-filter=ACMR "$base_ref" -- docs/archive/completed-phases)
else
  warn "Skipping changed archived-plan decision check; missing base ref $base_ref"
fi

while IFS= read -r -d '' f; do
  check_archived_plan_decision_record "$f"
done < <(git ls-files --others --exclude-standard -z docs/archive/completed-phases)

[[ "$decision_checked" -eq 1 ]] || ok "No changed archived plans"

# 5. Fossil references in current docs
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
  ! -path "*/.worktrees/*" \
  ! -path "./.claude/*" \
  ! -path "./docs/archive/*" \
  ! -path "./docs/decisions/*" \
  ! -path "./docs/performance/benchmark_history.md" \
  ! -name "ROADMAP.md" \
  -print0 | sort -z)
[[ "$fossil_hits" -eq 0 ]] && ok "No fossil references found"

# 5b. Backtick @pkg.Symbol references vs pkg.generated.mbti
#
# Catches stale API names in current docs automatically (issue #596).
# Same path exclusions as the fossil scan, plus submodule doc trees.
# Escape hatches: docs/symbol-check-allowlist.txt and inline HTML markers
# (see scripts/check-docs-symbols.py).
echo ""
echo "Backtick @pkg.Symbol references:"
symbol_hits=0
if ! python3 scripts/check-docs-symbols.py; then
  symbol_hits=1
fi
[[ "$symbol_hits" -eq 0 ]] || errors=$((errors + 1))

# 6. Doctest regression guard (warn)
#
# A package's top-level README.md that contains runnable MoonBit code fences
# should have a paired `README.mbt.md` (at package root when `source` is unset,
# or under `src/` when `source: "src"`) so `moon test` can exercise those
# snippets. Without the pair, Quick Start snippets drift silently as the API
# evolves (see the 2026-04-21 doctest migration).
#
# Opt-in — some READMEs are pure conceptual prose. Warn, don't fail.
echo ""
echo "Doctest regression guard:"
doctest_hits=0
while IFS= read -r -d '' modfile; do
  pkg=$(dirname "$modfile")
  readme="$pkg/README.md"
  [[ -f "$readme" ]] || continue

  # Runnable fence styles: ```moonbit, ```mbt, ```mbt check, ```mbt expect=...
  # Excluded: ```mbt nocheck (explicit opt-out), non-MoonBit languages.
  has_runnable=0
  if grep -qE '^```(moonbit|mbt)([[:space:]]+(check|expect=)|[[:space:]]*$)' "$readme"; then
    has_runnable=1
  fi

  [[ "$has_runnable" -eq 1 ]] || continue

  src=$(grep -o '"source":[[:space:]]*"[^"]*"' "$modfile" 2>/dev/null \
        | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true)
  expected="$pkg/${src:+$src/}README.mbt.md"

  if [[ ! -f "$expected" ]]; then
    warn "$readme has runnable MoonBit fences but no $expected"
    doctest_hits=1
  fi
done < <(find . -name "moon.mod.json" \
  ! -path "*/_build/*" \
  ! -path "*/.mooncakes/*" \
  ! -path "./.claude/*" \
  ! -path "*/.worktrees/*" \
  ! -path "./incr/*" \
  -print0 | sort -z)
[[ "$doctest_hits" -eq 0 ]] && ok "All packages with runnable snippets have README.mbt.md"

# 7. Relative links resolve
#
# Every path-like relative link in current docs must point at an existing
# file or directory. Catches link rot from file moves, renames, and dangling
# symlinks (e.g. the 2026-07-04 examples/*/README.md symlink rot).
#
# Excluded: docs/archive (historical docs legitimately reference deleted
# files), submodules (their docs belong to their own repos), and non-path
# targets (inline code like "Self[Ast](x)" and template placeholders like
# "<plan>.md" match the markdown link regex but are not links).
echo ""
echo "Relative links:"
link_rot=0
while IFS= read -r -d '' f; do
  dir=$(dirname "$f")
  while IFS= read -r raw; do
    link="${raw#](}"
    link="${link%)}"
    link="${link%% *}"        # drop optional "title"
    link="${link%%#*}"        # drop anchor
    [[ -z "$link" ]] && continue
    case "$link" in
      http://*|https://*|mailto:*|/*) continue ;;
    esac
    [[ "$link" == *"<"* || "$link" == *"["* ]] && continue
    # Only path-like targets: contain a slash or end in a known file extension
    if [[ "$link" != */* ]] &&
       [[ ! "$link" =~ \.(md|mbti|mbt|sh|py|mjs|json|tsv|toml|yml)$ ]]; then
      continue
    fi
    if [[ ! -e "$dir/$link" ]]; then
      fail "$f -> $link (missing)"
      link_rot=1
    fi
  done < <(grep -oE '\]\([^)]+\)' "$f" 2>/dev/null || true)
done < <(find . -name "*.md" \
  ! -path "*/_build/*" \
  ! -path "./.claude/*" \
  ! -path "*/.worktrees/*" \
  ! -path "*/.mooncakes/*" \
  ! -path "./docs/archive/*" \
  ! -path "./incr/*" \
  ! -path "./egraph/*" \
  ! -path "./egglog/*" \
  ! -path "./event-graph-walker/*" \
  -print0 | sort -z)
[[ "$link_rot" -eq 0 ]] && ok "All relative links resolve"

# 8. Active Plans reflect GitHub state
#
# Every "_Active:" entry in docs/README.md must cite an OPEN issue/PR —
# the first #NNN reference on the line is treated as the tracking issue.
# Catches shipped work still advertised as in-flight (found 2026-07-04:
# two entries claimed Active/pending for work merged weeks earlier).
#
# Needs gh with credentials (GH_TOKEN in CI); warn-skips offline.
echo ""
echo "Active plans state:"
active_lines=$(grep -n '^_Active:' docs/README.md || true)
if [[ -z "$active_lines" ]]; then
  ok "No _Active: entries"
elif ! command -v gh >/dev/null 2>&1; then
  warn "gh not available; skipping Active-plan state check"
else
  while IFS= read -r entry; do
    lineno="${entry%%:*}"
    issue=$(echo "$entry" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
    if [[ -z "$issue" ]]; then
      warn "docs/README.md:$lineno — _Active: entry cites no #issue"
      continue
    fi
    state=$(gh api "repos/dowdiness/loom/issues/$issue" --jq .state 2>/dev/null || echo "unknown")
    case "$state" in
      open)    ok "docs/README.md:$lineno — #$issue is open" ;;
      unknown) warn "docs/README.md:$lineno — could not query #$issue (offline or unauthenticated?)" ;;
      *)       fail "docs/README.md:$lineno — _Active: cites #$issue but it is $state; update the entry" ;;
    esac
  done <<< "$active_lines"
fi

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
