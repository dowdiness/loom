#!/bin/bash
# Verify a failed line-helper write leaves the existing lexer skeleton unchanged.
# Run from the loom repository root.
set -euo pipefail

FIXTURE=fixtures/line_lexer_regression
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/token" "$TMP/syntax"

moon run loomgen --target native -- \
  "$FIXTURE/src/line_lexer_src.mbt" \
  "$TMP/token" "$TMP/syntax" \
  --token-qual "" \
  --syntax-qual "" \
  --core-qual "@core"

cp "$TMP/syntax/lexer_skeleton.g.mbt" "$TMP/lexer_skeleton.before.mbt"
mkdir "$TMP/syntax/line_lexer.g.mbt"

if moon run loomgen --target native -- \
  "$FIXTURE/src/line_lexer_src.mbt" \
  "$TMP/token" "$TMP/syntax" \
  --token-qual "" \
  --syntax-qual "" \
  --core-qual "@core" \
  --line-lexer "$TMP/syntax/line_lexer.g.mbt"; then
  echo "expected --line-lexer helper write to fail" >&2
  exit 1
fi

cmp "$TMP/lexer_skeleton.before.mbt" "$TMP/syntax/lexer_skeleton.g.mbt"
