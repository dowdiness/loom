#!/bin/bash
# Regenerate line_lexer.g.mbt from the annotated source.
# Run from the loom repo root.
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
  --core-qual "@core" \
  --line-lexer "$FIXTURE/line_lexer.g.mbt"

moon fmt "$FIXTURE/line_lexer.g.mbt"
