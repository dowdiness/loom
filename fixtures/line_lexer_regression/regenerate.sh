#!/bin/bash
# Regenerate the line-lexer fixture's generated artifacts through Loomgen's
# canonical --regenerate-fixtures entry point. Run from the loom repo root.
#
# The generated skeleton keeps the handwritten lex_inline fallback and delegates
# the generated line-mode function. Formatting is the final committed-artifact
# normalization step after the emitter writes the two generated files.
set -euo pipefail

FIXTURE=fixtures/line_lexer_regression

moon run loomgen --target native -- --regenerate-fixtures
moon fmt loomgen/fixtures/ "$FIXTURE/line_lexer.g.mbt" "$FIXTURE/lexer_skeleton.g.mbt"
