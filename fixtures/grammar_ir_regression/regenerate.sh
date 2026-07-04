#!/bin/bash
# Regenerate grammar_ir.g.mbt from the source annotation files.
# Run from the loom repo root.
set -euo pipefail

FIXTURE=fixtures/grammar_ir_regression
TMP=$(mktemp -d)
mkdir -p "$TMP"/gir-token "$TMP"/gir-syntax

moon run loomgen --target native -- \
  "$FIXTURE"/src/token_src.mbt \
  "$TMP"/gir-token "$TMP"/gir-syntax \
  --term "$FIXTURE"/src/term_kind_src.mbt \
  --token-qual "" --syntax-qual "" \
  --grammar-ir "$FIXTURE"/grammar_ir.g.mbt \
  --language fixture

rm -rf "$TMP"
moon fmt "$FIXTURE"

