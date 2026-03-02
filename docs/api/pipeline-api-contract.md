# `pipeline` API Contract

**Package:** `dowdiness/loom/pipeline`
**Version target:** `0.1.0`
**Generated from:** `loom/src/pipeline/pkg.generated.mbti`

Every public symbol is listed below with its stability level and key invariants.
Symbols not listed here are package-private and subject to change without notice.

---

## Stability levels

- **Stable** — frozen for the 0.x series; breaking changes require a major version bump
- **Deprecated** — present for compatibility; will be removed in a future version
- **Deferred** — not included in 0.1.0; may be added in a later release

---

## `Parseable`

```moonbit
pub(open) trait Parseable {
  parse_source(Self, String) -> CstStage
}
```

**Stable.** The single method a language designer must implement. Combines lexing and
parsing into one step; the token type is hidden inside `Self` and never escapes.

**Contract:**
- If lexing fails, return a `CstStage` with `is_lex_error = true` and at least one
  entry in `diagnostics`. The `cst` field in this case should be a minimal valid
  (possibly empty) tree — see `@seam.build_tree([], root_kind)`.
- If lexing succeeds but parsing reports errors, return `is_lex_error = false` with
  `diagnostics` populated and a best-effort error-recovery tree in `cst`.
- If input is fully valid, return `is_lex_error = false` with `diagnostics` empty.
- **Never panic.** `parse_source` is called from inside a `Memo` closure; panics
  propagate uncaught to the calling `term()`.

| Symbol | Stability | Notes |
|---|---|---|
| `parse_source(Self, String) -> CstStage` | Stable | Fused lex + parse; Token type hidden in Self |

---

## `CstStage`

```moonbit
pub(all) struct CstStage {
  cst          : @seam.CstNode
  diagnostics  : Array[String]
  is_lex_error : Bool
}
```

**Stable.** The output of `Parseable::parse_source` and the value cached by
`ReactiveParser`'s first memo. All three fields are public for read access.

**Invariants:**
- `is_lex_error` is set explicitly by the `Parseable` implementation, never inferred
  from `cst.token_count` or diagnostic string prefixes. This makes lex-error routing
  in `ReactiveParser::term` robust to parser internals.
- `diagnostics` is `Array[String]` rather than a generic `Array[Diagnostic[T]]`
  because `Diagnostic[T]` does not derive `Eq`; normalized strings keep the `Eq`
  boundary clean for memo backdating.
- `CstStage::Eq` delegates to `CstNode::Eq` for the `cst` field, which uses a
  cached structural hash (O(1) rejection path). Two `CstStage` values can therefore
  be compared cheaply at the `Memo[CstStage]` boundary.
- When `is_lex_error = true`, `diagnostics` must be non-empty (at minimum one entry
  describing the lex failure).

| Symbol | Stability | Notes |
|---|---|---|
| `CstStage::{ cst, diagnostics, is_lex_error }` constructor | Stable | Direct construction; implementors set `is_lex_error` explicitly |
| `Eq` | Stable | `CstNode::Eq` uses cached hash — O(1) rejection; full structural check on hash collision |
| `Show` | Stable | Debug representation; format not guaranteed stable |

---

## `Language[Ast]`

```moonbit
pub struct Language[Ast] {
  // private fields
}
```

**Stable.** Token-erased vtable for a language definition. Three closure fields are
captured at construction time via `Language::from`; the token type disappears and only
`Ast` remains visible at the type level.

**Invariant:** Once constructed, a `Language[Ast]` value is immutable. All three
closures (`parse_source`, `to_ast`, `on_lex_error`) are captured by value and cannot
be replaced. Create a new `Language[Ast]` to change behaviour.

| Symbol | Stability | Notes |
|---|---|---|
| `Language::from[T : Parseable, Ast](T, to_ast~ : (SyntaxNode) -> Ast, on_lex_error~ : (String) -> Ast) -> Self[Ast]` | Stable | Bridge from trait implementor to vtable; erases Token via closure capture |

**Parameters to `Language::from`:**

| Parameter | Role |
|---|---|
| `lang : T` (positional) | Any `T : Parseable`; the token type lives only inside this value |
| `to_ast~ : (SyntaxNode) -> Ast` | Called by `ReactiveParser::term` on a successful parse; receives the root `SyntaxNode` |
| `on_lex_error~ : (String) -> Ast` | Called by `ReactiveParser::term` when `CstStage::is_lex_error` is true; receives the first diagnostic string |

---

## `ReactiveParser[Ast]`

```moonbit
pub struct ReactiveParser[Ast] {
  // private fields
}
```

**Stable.** Language-agnostic Salsa-style incremental pipeline. Internal topology:

```
source_text : Signal[String]
  → cst_memo  : Memo[CstStage]   — calls Language::parse_source
  → term_memo : Memo[Ast]        — calls Language::to_ast or Language::on_lex_error
```

**Invariants:**
- **Eq constraint asymmetry.** `ReactiveParser[Ast]` is unconstrained at the struct level.
  `new` and `term` require `Ast : Eq` (needed by `Memo::new` and `Memo::get` for
  backdating). `cst`, `diagnostics`, and `set_source` do not require `Ast : Eq`.
- **Backdating.** If `set_source` is called with a value equal to the current source
  (`String::Eq`), the `Signal` is a no-op and no memo runs. If a new source produces
  an equal `CstStage` (`CstStage::Eq`), `term_memo` is not marked stale. If
  `term_memo` recomputes and produces an equal `Ast` (`Ast : Eq`), `changed_at` is
  preserved — downstream memos (if any) are not dirtied.
- **Lifetime.** One `ReactiveParser` per document editing session. The `Runtime` is
  internal and not exposed.
- **`diagnostics()` returns a copy.** Mutating the returned `Array[String]` does not
  affect subsequent `diagnostics()` calls or the internal cache.

| Symbol | Stability | Notes |
|---|---|---|
| `ReactiveParser::new[Ast : Eq](String, Language[Ast]) -> Self[Ast]` | Stable | `Ast : Eq` required for memo backdating |
| `ReactiveParser::set_source[Ast](Self[Ast], String) -> Unit` | Stable | No-op when new source equals current source (`String::Eq`) |
| `ReactiveParser::cst[Ast](Self[Ast]) -> CstStage` | Stable | Triggers `cst_memo` evaluation if source changed; does not require `Ast : Eq` |
| `ReactiveParser::diagnostics[Ast](Self[Ast]) -> Array[String]` | Stable | Returns a defensive copy of `cst_memo.get().diagnostics` |
| `ReactiveParser::term[Ast : Eq](Self[Ast]) -> Ast` | Stable | Triggers both memos if needed; warm call is a staleness check only |

---

## Typical usage

```moonbit
// 1. Implement Parseable for your language:
struct MyLang {}
impl @pipeline.Parseable for MyLang with parse_source(_, s) { ... }

// 2. Build a Language[MyAst] vtable:
let lang : @pipeline.Language[MyAst] = @pipeline.Language::from(
  MyLang::{},
  to_ast=fn(syntax) { ... },
  on_lex_error=fn(msg) { MyAst::error(msg) },
)

// 3. Create a ReactiveParser and use it:
let db = @pipeline.ReactiveParser::new(initial_source, lang)
let ast  = @pipeline.ReactiveParser::term(db)
let diag = @pipeline.ReactiveParser::diagnostics(db)
@pipeline.ReactiveParser::set_source(db, new_source)  // invalidates memos
```

**Lambda calculus reference implementation:** `dowdiness/parser/lambda` provides
`LambdaLanguage`, `lambda_language()`, and `LambdaReactiveParser` as a worked example.

---

## Deferred API summary

No symbols are deferred from the 0.1.0 surface. Possible additions for 0.2.0:

| Candidate | Reason deferred |
|---|---|
| `ReactiveParser::reset(Self, String) -> Unit` | Alias for `set_source`; no current callers requesting it |
| Multi-language `ReactiveParser` (two `Language[Ast]` slots) | No identified use case; design unresolved |
