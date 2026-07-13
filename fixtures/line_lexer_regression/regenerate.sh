#!/bin/bash
# Regenerate the line-lexer fixture's generated artifacts from the annotated
# source. Run from the loom repo root.
#
# The skeleton (lexer_skeleton.g.mbt) is generated into the fixture directory
# WITHOUT --force-lexer, so an existing handwritten fallback (lex_inline)
# survives the migrate-in-place logic in loomgen. The line-mode helper
# (line_lexer.g.mbt) is fully regenerated on every run; its output is
# deterministic, so a second run leaves both generated files unchanged.
set -euo pipefail

FIXTURE=fixtures/line_lexer_regression
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/token"

moon run loomgen --target native -- \
  "$FIXTURE/src/line_lexer_src.mbt" \
  "$TMP/token" "$FIXTURE" \
  --skip-syntax \
  --token-qual "" \
  --syntax-qual "" \
  --core-qual "@core" \
  --line-lexer "$FIXTURE/line_lexer.g.mbt"

moon fmt "$FIXTURE/line_lexer.g.mbt" "$FIXTURE/lexer_skeleton.g.mbt"
