#!/usr/bin/env bash
# check-quickstart.sh — execute the root README's Quick Start commands.
#
# Extracts the first ```bash fence from README.md and runs it, so CI always
# exercises the commands users actually see — editing the README updates the
# check automatically, and a drifted or broken Quick Start fails CI instead
# of failing the next fresh clone (cf. issue #593, found by hand, not CI).
#
# Two documented commands are transformed rather than run verbatim:
#   - `git clone ... <url>`  → `git ls-remote --exit-code <url>` — CI must
#     test the checked-out revision, not a fresh clone of main; the ls-remote
#     still verifies the documented URL is real and reachable.
#   - the `cd <clone-dir>` line that follows the clone → skipped; the
#     working directory already is the repo root.
#   - `(cd <module-dir> && moon test)` → append `-p <moon.mod name>` so CI
#     exercises the documented module without fanning out to the whole workspace
#     (unscoped `moon test` from any member directory runs every workspace
#     member, including heavy native targets that can hang CI).
#
# Usage (from repo root):
#   bash scripts/check-quickstart.sh --tests   # all commands except `moon bench`
#   bash scripts/check-quickstart.sh --bench   # only the `moon bench` commands
#   bash scripts/check-quickstart.sh --list    # print the command partition
#
# The bench partition is separate because `moon bench --release` currently
# fails on a known bug (#593); CI runs it non-blocking until that is fixed.

set -euo pipefail

mode="${1:---tests}"

if [[ ! -f "README.md" ]]; then
  echo "Run from repo root (where README.md lives)." >&2
  exit 1
fi

# First ```bash fence in README.md
mapfile -t lines < <(awk '/^```bash$/{f=1; next} /^```$/{if (f) exit} f' README.md)

if [[ "${#lines[@]}" -eq 0 ]]; then
  echo "No \`\`\`bash fence found in README.md — Quick Start moved or renamed?" >&2
  exit 1
fi

run() {
  echo "+ $1"
  bash -c "$1"
}

# Map a `(cd <dir> && moon test)` Quick Start line to a module-scoped test.
# Returns the transformed command, or empty when the line is not a moon test.
scoped_moon_test_cmd() {
  local cmd="$1"
  if [[ ! "$cmd" =~ ^\(cd\ ([^[:space:]]+)\ \&\&\ moon\ test\)$ ]]; then
    return 1
  fi
  local dir="${BASH_REMATCH[1]}"
  if [[ ! -f "$dir/moon.mod" ]]; then
    echo "Quick Start moon test references missing moon.mod: $dir" >&2
    exit 1
  fi
  local module
  module=$(grep -m1 '^name = ' "$dir/moon.mod" | sed -E 's/^name = "([^"]+)".*/\1/')
  echo "(cd $dir && moon test -p $module)"
}

status=0
after_clone=0
for line in "${lines[@]}"; do
  cmd="${line%%#*}"                       # strip trailing comment
  cmd="$(echo "$cmd" | sed -e 's/[[:space:]]*$//')"
  [[ -z "$cmd" ]] && continue

  if [[ "$cmd" == git\ clone* ]]; then
    url=$(echo "$cmd" | grep -oE 'https?://[^ ]+' || true)
    if [[ -z "$url" ]]; then
      echo "Could not extract URL from documented clone command: $cmd" >&2
      exit 1
    fi
    case "$mode" in
      --list)  echo "[tests] git ls-remote --exit-code $url HEAD  (from: $cmd)" ;;
      --tests) run "git ls-remote --exit-code $url HEAD > /dev/null" ;;
    esac
    after_clone=1
    continue
  fi

  if [[ "$after_clone" -eq 1 && "$cmd" == cd\ * ]]; then
    [[ "$mode" == --list ]] && echo "[skip ] $cmd  (already at repo root)"
    after_clone=0
    continue
  fi

  if [[ "$cmd" == *"moon bench"* ]]; then
    case "$mode" in
      --list)  echo "[bench] $cmd" ;;
      --bench) run "$cmd" || status=1 ;;
    esac
  else
    scoped_cmd=""
    if scoped_cmd=$(scoped_moon_test_cmd "$cmd"); then
      case "$mode" in
        --list)  echo "[tests] $scoped_cmd  (from: $cmd)" ;;
        --tests) run "$scoped_cmd" ;;
      esac
    else
      case "$mode" in
        --list)  echo "[tests] $cmd" ;;
        --tests) run "$cmd" ;;
      esac
    fi
  fi
done

exit "$status"
