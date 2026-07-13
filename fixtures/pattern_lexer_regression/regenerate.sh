#!/bin/bash
# Regenerate pattern_lexer.g.mbt from the authoritative annotated source.
# Run from the loom repository root.
set -euo pipefail

FIXTURE=fixtures/pattern_lexer_regression
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

moon run loomgen --target native -- \
  "$FIXTURE"/src/pattern_lexer_src.mbt \
  "$TMP"/token "$TMP"/syntax \
  --skip-syntax \
  --lexer "$FIXTURE"/pattern_lexer.g.mbt
moon fmt "$FIXTURE"/pattern_lexer.g.mbt
