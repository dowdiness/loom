# `incremental` API Contract

**Package:** `dowdiness/loom/incremental`
**Version target:** `0.1.0`
**Generated from:** `loom/src/incremental/pkg.generated.mbti`

Every public symbol is listed below with its stability level and key invariants.
Symbols not listed here are package-private and subject to change without notice.

---

## Stability levels

- **Stable** — frozen for the 0.x series; breaking changes require a major version bump
- **Deprecated** — present for compatibility; will be removed in a future version
- **Deferred** — not included in 0.1.0; may be added in a later release

---

## `ImperativeParser[Ast]`

```moonbit
pub struct ImperativeParser[Ast] {
  // all fields private
}
```

**Stable.** Edit-driven incremental parser using the Wagner-Graham damage tracking strategy.
All internal state (source, tree, syntax tree, reuse count, CST hash) is private and managed by
the parser. Language-specific behaviour is injected via `ImperativeLanguage[Ast]` vtable.

**Internal topology:**

```
source : String
  → full_parse  : (String) -> ParseOutcome   — initial parse
  → incr_parse  : (String, SyntaxNode, Edit) -> ParseOutcome — edit reparse
  → to_ast      : (SyntaxNode) -> Ast        — CST → AST (skipped on hash match)
```

**Invariants:**
- **Fields all private.** Callers cannot directly observe or mutate `source`, `tree`,
  `syntax_tree`, `last_reuse_count`, or `prev_cst_hash`. Use the accessor methods.
- **CST equality skip.** Both `parse()` and `edit()` skip `to_ast` when the new CstNode
  hash matches the previous hash, returning the cached Ast instead. This is transparent
  to callers — correctness is unaffected because the CST is structurally identical.
- **Global interners.** Token deduplication (`core_interner`) and node deduplication
  (`core_node_interner`) are process-level globals, accumulated across all parse calls
  and never cleared. Multiple parsers sharing a process share these interners.
- **Lifetime.** One `ImperativeParser` per document editing session. Call `reset()` to
  resync with a structurally regenerated source; create a new parser only when the
  document identity changes.

| Symbol | Stability | Notes |
|---|---|---|
| `ImperativeParser::new[Ast](String, ImperativeLanguage[Ast]) -> Self[Ast]` | Stable | Prefer `new_imperative_parser` from `@loom`; this constructor is for advanced use |
| `ImperativeParser::parse[Ast](Self[Ast]) -> Ast` | Stable | Full parse from `self.source`; reuse count → 0 |
| `ImperativeParser::edit[Ast](Self[Ast], Edit, String) -> Ast` | Stable | Incremental reparse; falls back to `parse()` if no prior tree |
| `ImperativeParser::reset[Ast](Self[Ast], String) -> Ast` | Stable | Discard all incremental state, full parse of new source |
| `ImperativeParser::get_source[Ast](Self[Ast]) -> String` | Stable | Current source text |
| `ImperativeParser::get_tree[Ast](Self[Ast]) -> Ast?` | Stable | Cached Ast from last `parse`/`edit`/`reset`; `None` before first call |
| `ImperativeParser::diagnostics[Ast](Self[Ast]) -> Array[String]` | Stable | Normalized parse diagnostics from last successful parse |
| `ImperativeParser::get_last_reuse_count[Ast](Self[Ast]) -> Int` | Stable | CST nodes reused in last `edit()` call; 0 for `parse()` and `reset()` |

---

## `new_imperative_parser` factory

```moonbit
// From @loom:
pub fn[T, K, Ast] new_imperative_parser(
  source  : String,
  grammar : Grammar[T, K, Ast],
) -> @incremental.ImperativeParser[Ast]
```

**Stable.** Preferred construction path. Erases `T` (token type) and `K` (kind type)
into closures so callers only see `Ast`. Creates fresh `TokenBuffer` and diagnostic
state per parser; global interners are shared across parsers.

---

## `ImperativeLanguage[Ast]`

```moonbit
pub struct ImperativeLanguage[Ast] {
  // all fields private
}
```

**Stable (advanced use).** Token-erased vtable for incremental language integration.
Analogous to `@pipeline.Language[Ast]`. Constructed via `ImperativeLanguage::new`.

Grammar authors never need to construct `ImperativeLanguage` directly — the
`new_imperative_parser` factory handles this wiring.

| Symbol | Stability | Notes |
|---|---|---|
| `ImperativeLanguage::new[Ast](full_parse~, incremental_parse~, to_ast~, on_lex_error~, get_diagnostics~) -> Self[Ast]` | Stable | All parameters are labelled closures |

---

## `ParseOutcome`

```moonbit
pub(all) enum ParseOutcome {
  Tree(@seam.SyntaxNode, Int)
  LexError(String)
}
```

**Stable (advanced use).** Returned by `full_parse` and `incremental_parse` closures.
`Tree` carries the new syntax tree and the CST reuse count (0 for full parses).
`LexError` carries the error message for `on_lex_error` dispatch.

---

## Typical usage

```moonbit
// 1. Construct via @loom factory (preferred):
let parser = @loom.new_imperative_parser("λx.x", lambda_grammar)

// 2. Initial parse:
let ast = parser.parse()

// 3. Incremental edit (e.g. user changes "x" to "y"):
let edit = @core.Edit::replace(1, 2, 2)
let ast2 = parser.edit(edit, "λy.y")

// 4. Inspect diagnostics:
let diags = parser.diagnostics()  // [] on success

// 5. Reset after structural regeneration:
let ast3 = parser.reset("λz.z + 1")  // discards incremental state
```

---

## Deferred API summary

| Candidate | Reason deferred |
|---|---|
| Streaming / async `edit` | No identified use case; design unresolved |
| `ImperativeParser` → reactive `Signal` bridge | Would expose `ImperativeLanguage` in `@incr` API |
