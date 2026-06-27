# loomgen

Code generator for loom language plumbing files.

Phase 1: reads `#loom.*`-annotated `Token` enum, emits `syntax_kind.g.mbt` and `token_impls.g.mbt`.

Usage: `moon run loomgen --target native -- [--seed <syntax.mbt>] <token.mbt> [token_out_dir] [syntax_out_dir]`
See `HANDOFF.md` for examples.
