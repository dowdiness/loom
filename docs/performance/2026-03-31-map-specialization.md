# Closure Specialization vs Generic Map — Performance Snapshot

**Date:** 2026-03-31
**Context:** PR #64, replacing `re_intern_tokens_only` with `CstElement::map`

## Finding

Specializing a closure's type signature does not improve performance in wasm-gc.
A `map_tokens` method with `(CstToken) -> CstToken` was **20% slower** than
the generic `map` with `(CstElement) -> CstElement`, despite doing strictly
less work (no closure dispatch on Node elements).

## Numbers

50 reuse nodes × 100 tokens each, wasm-gc `--release`:

| Approach | Time | vs hand-written |
|----------|------|-----------------|
| Hand-written `re_intern_tokens_only` | 154.5 µs | 1.00x |
| `CstElement::map` + `(CstElement) -> CstElement` | 174.5 µs | 1.13x |
| `CstElement::map_tokens` + `(CstToken) -> CstToken` | 208.7 µs | 1.35x |

## Explanation

The wasm-gc compiler monomorphizes closures by type. The narrower
`(CstToken) -> CstToken` signature produced different (worse) codegen than
`(CstElement) -> CstElement`. This aligns with the cst-transform research
finding: **allocation is the dominant cost in wasm-gc, not closure dispatch**.
The ~1.10x overhead from indirect `call_ref` is a reliable floor that
specialization cannot meaningfully reduce.

## Takeaway

Prefer the generic `map` over specialized variants. Don't add `map_tokens`,
`map_nodes`, etc. unless benchmarks prove they're faster. The 13% overhead
of `map` vs hand-written is the cost of abstraction — acceptable for code
that runs once per incremental reuse event.
