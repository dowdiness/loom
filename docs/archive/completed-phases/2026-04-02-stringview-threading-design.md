# StringView Threading — Zero-Copy Token Text

**Date:** 2026-04-02
**Status:** Complete
**Scope:** seam (ParseEvent, CstToken, Interner), loom/core (ParserContext)
**Issue:** #61

---

## Goal

Eliminate intermediate String allocations in the lex→parse→CST pipeline by
threading `StringView` (a non-owning slice into the source string) through the
hot path. String materialization deferred to the interner miss path only.

**Measured bottleneck:** For 110 tokens with 20-char identifiers, the
parse-to-CST pipeline (`token_text_at` + event passing + interning) costs
~39 µs — 86% of full parse time. The lexer accumulator (1.3 µs) is not the
bottleneck.

**Expected result:** Zero String allocations on the interner hit path.
~110 fewer intermediate allocations per parse of a 110-token file.

---

## Design

### Pipeline change

**Before:**
```
source: String
  → token_text_at: source[start:end].to_string()     ← ALLOC per token
  → ParseEvent::Token(kind, text: String)             ← carries String
  → build_tree: CstToken::new(kind, text: String)     ← stores String
  → interner: HashMap[String, CstToken] lookup        ← on hit: String wasted
```

**After:**
```
source: String
  → token_text_at: source[start:end]                  ← zero-copy StringView
  → ParseEvent::Token(kind, view: StringView)          ← carries view
  → build_tree: interner.intern_token(kind, view)
      → hit:  return cached CstToken                   ← zero alloc
      → miss: view.to_string() → CstToken::new         ← ALLOC (once per unique)
```

### File-by-file changes

**1. `loom/src/core/parser.mbt` — `token_text_at` returns `StringView`**

- Return type: `String` → `StringView`
- Fast path: `self.source[start:end]` (no `.to_string()`)
- Surrogate slow path removed: `StringView` slicing does not validate UTF-16,
  preserving raw code units for CRDT sync fidelity. Surrogate handling moves
  to point-of-use (display, not parsing).
- `emit_token` and `flush_trivia` pass `StringView` to `ParseEvent::Token`.

**2. `seam/event.mbt` — `ParseEvent::Token` carries `StringView`**

- `Token(RawKind, String)` → `Token(RawKind, StringView)`
- `build_tree`: calls `view.to_string()` when constructing `CstToken::new`.
- `build_tree_interned`: passes `StringView` to `interner.intern_token`.
- `build_tree_fully_interned`: passes `StringView` to `interner.intern_token`.
- `re_intern_subtree` and ReuseNode paths pass `CstToken.text` (String) to
  `intern_token` — auto-coerced to `StringView` by the compiler.

**3. `seam/interner.mbt` — `intern_token` accepts `StringView`**

- Signature: `intern_token(kind: RawKind, text: String)` →
  `intern_token(kind: RawKind, text: StringView)`
- Inner HashMap key: `HashMap[String, CstToken]` → `HashMap[StringView, CstToken]`
- Hit path: `StringView` lookup (hash + eq by content) — zero alloc.
- Miss path: `text.to_string()` once for `CstToken.text` field. Store the
  `StringView` as key (keeps source alive via GC — same lifetime as parse session).

**4. `seam/cst_node.mbt` — `CstToken::new` accepts `StringView`**

- `CstToken::new(kind: RawKind, text: String)` →
  `CstToken::new(kind: RawKind, text: StringView)`
- Internally calls `text.to_string()` to store as owned `String`.
- Public `text: String` field unchanged — position-independent, all downstream
  consumers unaffected.

### What does NOT change

- `CstToken.text: String` field
- `SyntaxToken.text()` return type
- `SyntaxNode` and all downstream consumers
- Incremental reuse / cursor protocol
- `CstNode` interning

### StringView GC semantics

`StringView.data()` returns the backing `String`, so the GC keeps the source
alive as long as any view exists. Since the interner is session-scoped (one per
parse session), StringView keys have the same lifetime as the source string
itself. No new GC pressure.

### Backward compatibility

`ParseEvent` is `pub(all)`. Changing `Token(RawKind, String)` to
`Token(RawKind, StringView)` is a source-level signature change. However,
MoonBit auto-coerces `String` → `StringView` in enum constructors and
function arguments, so **no callsite changes are needed** for:
- String literals: `ParseEvent::Token(kind, "hello")` — compiles as-is
- String variables: `ParseEvent::Token(kind, t.text)` — auto-coerced
- Function calls: `intern_token(kind, some_string)` — auto-coerced

~40+ callsites in tests/benchmarks confirmed unaffected by auto-coercion.

---

## Validation

1. **All existing tests pass** across seam, loom, lambda, json, markdown
2. **Zero-copy benchmarks** (`zero_copy_benchmark.mbt`) show measurable speedup
   on full parse, especially long identifiers (before: 45.81 µs, target: <35 µs)
3. **Surrogate round-trip test** — tokens containing lone surrogates survive
   StringView threading and produce correct `CstToken.text`

### Commands

```bash
cd loom && moon check && moon test
cd seam && moon check && moon test
cd examples/lambda && moon check && moon test
cd examples/json && moon check && moon test
cd examples/lambda && moon bench --release -p dowdiness/lambda/benchmarks -f zero_copy_benchmark.mbt
```

---

## Benchmark results

110 tokens, `--release`, native target:

| Input | Tokenize (before) | Tokenize (after) | Full Parse (before) | Full Parse (after) | Speedup |
|-------|-------------------|------------------|---------------------|--------------------|---------|
| Integers (`1+2+...+55`) | 2.80 µs | 2.58 µs | 28.69 µs | **24.97 µs** | **13%** |
| Short identifiers (`a+b+...`) | 5.09 µs | 4.88 µs | 30.62 µs | **27.64 µs** | **10%** |
| Long identifiers (20 chars each) | 6.35 µs | 6.05 µs | 45.81 µs | **35.35 µs** | **23%** |

Tokenize times barely changed (lexer not modified). Full parse speedup comes from
eliminating ~110 intermediate String allocations per parse in the
`token_text_at` → `ParseEvent` → `Interner` pipeline.
