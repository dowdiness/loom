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
All internal state (source, current snapshot, reuse count, CST hash) is private
and managed by the parser. Language-specific behaviour is injected via the
`ImperativeLanguage[Ast]` vtable.

**Internal topology:**

```
source : String
  → full_parse  : (String) -> (SyntaxNode, DiagnosticSet, Int)
  → incr_parse  : (String, SyntaxNode, Edit) -> (SyntaxNode, DiagnosticSet, Int)
  → to_ast      : (SyntaxNode) -> Ast        — CST → AST (skipped on structural equality)
  → snapshot    : ParseSnapshot[Ast]
```

**Invariants:**
- **Fields all private.** Callers cannot directly observe or mutate `source`,
  `snapshot`, or `prev_cst`. Use the accessor methods.
- **CST equality skip.** Both `parse()` and `edit()` skip `to_ast` when the new
  `CstNode` compares equal to the cached one (`CstNode::Eq` — structural equality using
  kind + children, with hash as a fast rejection path). This is transparent to callers.
- **Source-span CST tokens.** The generic parser builds non-interned CSTs so
  token text remains a zero-copy source span. Incremental reuse emits validated
  reuse events and rebuilds current-source token spans/nodes rather than relying
  on process-global node/token interners or direct-splicing old CST objects.
- **Lifetime.** One `ImperativeParser` per document editing session. Call `reset()` to
  resync with a structurally regenerated source; create a new parser only when the
  document identity changes.

| Symbol | Stability | Notes |
|---|---|---|
| `ImperativeParser::new[Ast](String, ImperativeLanguage[Ast]) -> Self[Ast]` | Stable | Prefer `new_imperative_parser` from `@loom`; this constructor is for advanced use |
| `ImperativeParser::parse[Ast](Self[Ast]) -> ParseSnapshot[Ast]` | Stable | Full parse from `self.source`; returns source, syntax, AST, diagnostics, and reuse count |
| `ImperativeParser::edit[Ast](Self[Ast], Edit, String) -> ParseSnapshot[Ast]` | Stable | Incremental reparse; falls back to `parse()` if no prior snapshot |
| `ImperativeParser::reset[Ast](Self[Ast], String) -> ParseSnapshot[Ast]` | Stable | Discard all incremental state, full parse of new source |
| `ImperativeParser::current[Ast](Self[Ast]) -> ParseSnapshot[Ast]?` | Stable | Cached snapshot from the last parse/edit/reset; `None` before first call |
| `ImperativeParser::get_source[Ast](Self[Ast]) -> String` | Stable | Current source text |
| `ImperativeParser::get_tree[Ast](Self[Ast]) -> Ast?` | Stable | Cached Ast from last `parse`/`edit`/`reset`; `None` before first call |
| `ImperativeParser::diagnostics[Ast](Self[Ast]) -> DiagnosticSet` | Stable | Structured diagnostics from the current snapshot, or empty before first parse |
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
state per parser; unchanged regions are emitted through parser-owned reuse
events that rebase token spans to the current source during tree build.

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
| `ImperativeLanguage::new[Ast](full_parse~, incremental_parse~, to_ast~, get_fold_stats?) -> Self[Ast]` | Stable | All parameters are labelled closures; parse closures return `(SyntaxNode, DiagnosticSet, Int)` |

---

## Typical usage

```moonbit
// 1. Construct via @loom factory (preferred):
let parser = @loom.new_imperative_parser("(x) => x", lambda_grammar)

// 2. Initial parse:
let snapshot = parser.parse()
let ast = snapshot.ast

// 3. Incremental edit (e.g. user changes the body "x" to "y"):
let edit = @core.Edit::replace(7, 8, 8)
let snapshot2 = parser.edit(edit, "(x) => y")
let ast2 = snapshot2.ast

// 4. Inspect diagnostics:
let diags = parser.diagnostics()  // DiagnosticSet::empty() on success

// 5. Reset after structural regeneration:
let ast3 = parser.reset("(z) => z + 1").ast  // discards incremental state
```

---

## Deferred API summary

| Candidate | Reason deferred |
|---|---|
| Streaming / async `edit` | No identified use case; design unresolved |
| `ImperativeParser` → reactive `Input` bridge | Would expose `ImperativeLanguage` in `@incr` API |
