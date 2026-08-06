#!/usr/bin/env bash
# PROTOTYPE — THROWAWAY. Interactive shell for issue #890.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
module_root=$(cd "$here/../../.." && pwd)
cd "$module_root"

count=$(NEW_MOON_MOD=0 moon run src/tools/inline_plan_prototype/tui --target native -- --count)
index=0

while true; do
  printf '\033[2J\033[H'
  printf '#890 CONTAINER-LOCAL INLINE PLAN PROTOTYPE\n'
  printf 'scenario %d/%d\n\n' "$((index + 1))" "$count"
  NEW_MOON_MOD=0 moon run src/tools/inline_plan_prototype/tui --target native -- --index "$index"
  printf '\n[n] next  [p] previous  [a] all verdicts  [b] work scaling  [q] quit\n'
  IFS= read -r action || exit 0
  case "$action" in
    n|'') index=$(((index + 1) % count)) ;;
    p) index=$(((index + count - 1) % count)) ;;
    a)
      printf '\033[2J\033[H'
      NEW_MOON_MOD=0 moon run src/tools/inline_plan_prototype/tui --target native -- --all
      printf '\nPress Enter to return.\n'
      IFS= read -r _ || exit 0
      ;;
    b)
      printf '\033[2J\033[H'
      NEW_MOON_MOD=0 moon run src/tools/inline_plan_prototype/tui --target native -- --stress
      printf '\nPress Enter to return.\n'
      IFS= read -r _ || exit 0
      ;;
    q) exit 0 ;;
  esac
done
