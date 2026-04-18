# Plan: Unified Parser Implementation

**Date:** 2026-04-17
**Status:** In progress — Stages 1–2 complete (2026-04-18); Stages 3–6 pending. ADR [2026-04-17](../decisions/2026-04-17-unified-parser-proposal.md) Accepted.

Implementation plan for the unified `Parser[Ast]` proposed in the ADR. The ADR
captures motivation, scoping, and decision principles; this plan captures the
concrete API surface, internal structure, and the staged file-by-file
migration across loom + canopy.

## Scope

This plan covers everything needed to replace `ReactiveParser[Ast]` with a
unified `Parser[Ast]` that wraps `ImperativeParser[Ast]`. Stages 1–3 are
isolated to loom. Stage 4 is cross-cutting across canopy editor core, the
three canopy language companions (lambda, json, markdown), and the lambda FFI.
Stages 5–6 deprecate and remove `ReactiveParser`.

## Public API (new `Parser[Ast]` in `loom/src/pipeline/`)

### Update paths

```moonbit
pub fn[Ast : Eq] Parser::set_source(
  self : Parser[Ast],
  source : String,
) -> Unit

pub fn[Ast : Eq] Parser::apply_edit(
  self : Parser[Ast],
  edit : Edit,
  new_source : String,
) -> Unit
```

### Reactive accessors (read-only `@incr.Memo` views)

```moonbit
pub fn[Ast] Parser::source(self : Parser[Ast]) -> @incr.Memo[String]
pub fn[Ast] Parser::syntax_tree(self : Parser[Ast]) -> @incr.Memo[@seam.SyntaxNode?]
pub fn[Ast] Parser::ast(self : Parser[Ast]) -> @incr.Memo[Ast]
pub fn[Ast] Parser::diagnostics(self : Parser[Ast]) -> @incr.Memo[Array[String]]
pub fn[Ast] Parser::runtime(self : Parser[Ast]) -> @incr.Runtime
```

`@incr.Memo` has no public `.set()`, giving read-only semantics in normal
use. Callers `.get()` inside downstream memo closures to register a
dependency edge.

**Caveat (capability-safety, not value-safety):** `Memo::dependencies()` +
`Runtime::dispose_cell()` lets a sufficiently motivated caller discover and
invalidate the private `Signal` cells once `runtime()` is exposed.
Preventing that would require a newtype wrapper that hides the `Runtime`
and `Memo::dependencies()`. Treat normal use as safe; treat deliberate
dependency-walking as out of contract.

## Internal structure (sketch — finalize during Stage 1)

```moonbit
pub struct Parser[Ast] {
  priv engine : ImperativeParser[Ast]
  priv rt : @incr.Runtime
  priv source_signal : @incr.Signal[String]                    // private
  priv syntax_signal : @incr.Signal[@seam.SyntaxNode?]         // private
  priv ast_signal : @incr.Signal[Ast]                           // private
  priv diagnostics_signal : @incr.Signal[Array[String]]        // private
  priv source_view : @incr.Memo[String]                         // public via source()
  priv syntax_view : @incr.Memo[@seam.SyntaxNode?]              // public via syntax_tree()
  priv ast_view : @incr.Memo[Ast]                               // public via ast()
  priv diagnostics_view : @incr.Memo[Array[String]]             // public via diagnostics()
}

fn[Ast : Eq] Parser::new(
  source : String,
  lang : @incremental.ImperativeLanguage[Ast],
) -> Parser[Ast] {
  // Prime the engine: a fresh ImperativeParser has tree/syntax_tree slots
  // unset until parse/edit/reset runs. Call parse() here so the initial
  // signal values reflect a real parse, not None.
  let engine = @incremental.ImperativeParser::new(source, lang)
  let initial_ast = engine.parse()
  let initial_syntax = engine.get_syntax_tree()
  let initial_diagnostics = engine.diagnostics()
  let rt = @incr.Runtime::new()
  let source_signal = @incr.Signal::new(rt, source, label="source")
  let syntax_signal = @incr.Signal::new(rt, initial_syntax, label="syntax")
  let ast_signal = @incr.Signal::new(rt, initial_ast, label="ast")
  let diagnostics_signal = @incr.Signal::new(rt, initial_diagnostics, label="diagnostics")
  let source_view = @incr.Memo::new(rt, () => source_signal.get(), label="source-view")
  let syntax_view = @incr.Memo::new(rt, () => syntax_signal.get(), label="syntax-view")
  let ast_view = @incr.Memo::new(rt, () => ast_signal.get(), label="ast-view")
  let diagnostics_view = @incr.Memo::new(rt, () => diagnostics_signal.get(), label="diagnostics-view")
  { engine, rt, source_signal, syntax_signal, ast_signal, diagnostics_signal,
    source_view, syntax_view, ast_view, diagnostics_view }
}

pub fn[Ast : Eq] Parser::set_source(self : Parser[Ast], source : String) -> Unit {
  self.rt.batch(() => {
    let ast = self.engine.reset(source)
    self.source_signal.set(source)
    self.syntax_signal.set(self.engine.get_syntax_tree())
    self.ast_signal.set(ast)
    self.diagnostics_signal.set(self.engine.diagnostics())
  })
}

pub fn[Ast : Eq] Parser::apply_edit(
  self : Parser[Ast],
  edit : Edit,
  new_source : String,
) -> Unit {
  self.rt.batch(() => {
    let ast = self.engine.edit(edit, new_source)
    self.source_signal.set(new_source)
    self.syntax_signal.set(self.engine.get_syntax_tree())
    self.ast_signal.set(ast)
    self.diagnostics_signal.set(self.engine.diagnostics())
  })
}
```

### Notes on the sketch

- Uses the real `ImperativeParser` API: `parse()` / `edit()` / `reset()`
  return `Ast` directly; `get_syntax_tree() -> SyntaxNode?` returns the CST
  (None after a lex error — hence `Signal[SyntaxNode?]`);
  `diagnostics() -> Array[String]` returns the language's current
  diagnostic array.
- Constructor takes `@incremental.ImperativeLanguage[Ast]` directly for
  self-containment. The real `Parser::new` may wrap a higher-level
  `@pipeline.Language[Ast]` with an adapter — decide during Stage 1 PR
  review.
- The reactive layer is a thin publication mechanism, not the compute
  graph: all four `Signal` cells are written imperatively after the engine
  has advanced, inside one `Runtime::batch`. The four `*_view` Memos are
  pass-throughs whose only job is to give callers a read-only handle with
  a real dependency edge to the underlying signal. Node-level reuse
  happens entirely inside `engine`; `@incr` never drives parsing.

## `attach_typecheck` migration shape

The existing helper in `examples/lambda/src/typed_parser.mbt` retargets
from `ReactiveParser[Term]` to `(Runtime, Memo[SyntaxNode?])` or, equivalently, a
`Parser` handle. The callback typechecks from the published CST — matching
the canopy FFI path, which operates on CST rather than `Term` because
`Term` drops lambda annotations.

```moonbit
let typed_memo : @incr.Memo[TypedTerm] = scope.memo(fn() {
  match parser.syntax_tree().get() {
    Some(tree) => @typecheck.convert_from_cst(tree)
    None => TypedTerm::Error("parse")   // lex / recoverable parse failure
  }
}, label="typed_term_bridge")
```

The `None` branch is load-bearing: parse-error states must stay
non-aborting and recover on later edits. Existing `typed_parser_test.mbt`
coverage asserts this.

## Migration stages

Staged over multiple PRs. Each stage compiles and passes all tests.

### Stage 1 — Introduce `Parser[Ast]` alongside `ReactiveParser`

Add the new type in `loom/src/pipeline/`. Implement `set_source`,
`apply_edit`, `source()`, `syntax_tree()`, `ast()`, `diagnostics()`,
`runtime()`. No changes to existing `ReactiveParser`.

**Resolutions expected in the Stage 1 PR** (moved here from the ADR —
these are implementation-shaped decisions, not principle-level):

- **Constructor shape.** Whether `Parser::new` wraps a higher-level
  `@pipeline.Language[Ast]` or takes `ImperativeLanguage[Ast]` directly.
  Pick whichever yields the more ergonomic call sites in the canopy
  companions; lean toward mirroring today's `ReactiveParser::new` for
  drop-in familiarity.
- **Runtime-injection shape.** The ADR decides to preserve external
  runtime injection (today's `from_parts` capability). Concrete shape to
  finalize: a second constructor `Parser::from_parts(rt, ...)` mirroring
  `ReactiveParser::from_parts`, or a labeled parameter on `Parser::new`.
  Pick based on which is less redundant with the wrapping-Language
  decision above.
- **Final type name.** `Parser[Ast]` collides mentally with
  language-specific parsers (`lambda_grammar` etc.). Alternatives:
  `Document[Ast]` (mizchi), `ParserSession[Ast]` (explicit).
  Bikeshedding question — finalize during PR review, not before.
- **`Editable` trait on `apply_edit`.** `ImperativeParser::edit` takes
  `Edit` directly; keep that shape by default. Add an `Editable`
  overload only if a concrete use case emerges during Stage 1.

### Stage 2 — Retarget `attach_typecheck` to `Memo[SyntaxNode?]`

Generalize `attach_typecheck` in `examples/lambda/src/typed_parser.mbt`
from `ReactiveParser[Term]` to `(Runtime, Memo[SyntaxNode?])` (or a
`Parser` handle). Pattern-match shape as above. Add tests against
`Parser`.

### Stage 3 — Migrate example tests and benchmarks

Move `reactive_parser_test.mbt` and the lambda reactive benchmarks to use
`Parser`. Assert equivalent output. Retain coverage of both update paths
(`apply_edit` and `set_source`).

### Stage 4 — Migrate `SyncEditor` and downstream bundles (canopy)

Cross-cutting change across all three canopy languages, not a single
field swap. Expect to land as a multi-commit PR (likely one commit per
language). This is the commit sequence that delivers the canopy web demo.

**Editor core (generic, all languages):**

- **`editor/sync_editor.mbt`** — `SyncEditor::new_generic` currently owns
  an `ImperativeParser` plus independent `source_text` / `syntax_tree`
  signals. Replace with a `Parser` handle; route all signal consumers to
  `parser.source()` / `parser.syntax_tree()`.
- **`editor/sync_editor_parser.mbt`** — today batches paired
  `source_text` + `syntax_tree` updates under `Runtime::batch`. That
  logic moves inside `Parser::apply_edit` / `set_source`, eliminating
  the external batching requirement.
- **`core/projection_memo.mbt`** — `build_projection_memos` currently
  takes `syntax_tree : @incr.Signal[SyntaxNode?]`. Retarget to
  `Memo[SyntaxNode?]`, matching the new Parser surface.

**Per-language companions (subscribe to the shared parser):**

- **`lang/lambda/companion/lambda_editor.mbt`** — `build_memos` wires
  projection, eval, and escalation memos together. All of these consume
  the editor-owned `syntax_tree : Signal[SyntaxNode?]` plus parser AST
  access today. Retarget to
  `(parser.runtime(), parser.syntax_tree(), parser.ast())`.
- **`lang/lambda/eval/eval_memo.mbt`** — `build_eval_memo` consumes the
  reactive syntax tree; retarget to `parser.syntax_tree()`.
- **`lang/lambda/eval/batch_escalation.mbt`** — `build_escalation_memo`
  ditto.
- **`lang/lambda/flat/projection_memo.mbt`** — lambda-specific flat
  projection that reads `Signal[SyntaxNode?]` directly; retarget to
  `parser.syntax_tree()` alongside the generic `core/projection_memo.mbt`.
- **`lang/json/companion/json_editor.mbt`** and
  **`lang/json/proj/json_memo.mbt`** — same retargeting as lambda,
  without the eval/escalation pieces.
- **`lang/markdown/companion/markdown_editor.mbt`** and
  **`lang/markdown/proj/markdown_memo.mbt`** — same retargeting.

**FFI (lambda — the double-parse removal):**

- **`ffi/lambda/lifecycle.mbt` `TypecheckBundle`** — currently maintains
  a *separate* `Runtime` + `Scope` + `text_signal` + output `Memo`
  because *"LambdaCompanion does not expose its runtime to FFI"*.
  Unifying parser + runtime ownership in `Parser` is exactly what lets
  this bundle drop its private `text_signal` and subscribe to the
  editor's `parser.syntax_tree()` on the shared runtime. This is the
  double-parsing removal that motivates the ADR.
- **`ffi/lambda/undo.mbt`** — also calls `new_typecheck_bundle()`;
  migrate alongside `lifecycle.mbt`.
- **`ffi/lambda/diagnostics.mbt`** — `get_diagnostics_json` reads the
  bundle's output Memo; update call sites to the unified attachment
  point.

### Stage 5 — Deprecate `ReactiveParser`

Add `@deprecated` annotation (if MoonBit supports; otherwise a doc
comment). Update `docs/api/choosing-a-parser.md` to route all new
consumers to `Parser`. Schedule removal after one release cycle.

### Stage 6 — Remove `ReactiveParser`

Delete the struct and all tests. Update `docs/decisions/` archive pointer
to the ADR. Move this plan file to `docs/archive/completed-phases/`.

## Validation checkpoints

- **After Stage 1:** `moon test -p dowdiness/loom/pipeline` green;
  `.mbti` for the new `Parser` surface is stable.
- **After Stage 2:** lambda example tests including
  `typed_parser_test.mbt` green — parse-error recovery still
  non-aborting.
- **After Stage 3:** all loom module tests green; benchmarks show
  `Parser::apply_edit` within noise of `ImperativeParser::edit` (same
  engine, just a signal-set layer on top).
- **After Stage 4:** canopy `moon test` green across all three
  languages; web demo loads with typecheck, projection, eval, and
  escalation memos wired off the shared `Parser`; no `TypecheckBundle`
  private `Runtime`.
- **After Stage 5:** no new loom consumer references `ReactiveParser`.
- **After Stage 6:** `ReactiveParser` source and tests removed; no
  dangling references in docs.

## Non-goals

- Introducing a token-stage cutoff inside `Parser`. The regression is
  accepted; re-adding it is a follow-up ADR if a consumer demonstrates
  need.
- Converting to CST-as-source-of-truth. That is a separate, larger
  decision flagged as future trajectory in ADR 2026-03-02.
- Changing the `@incr` public API, the `seam` CST model, or
  `ImperativeParser`'s engine internals.

## References

- [ADR 2026-04-17: Unified Parser](../decisions/2026-04-17-unified-parser-proposal.md) — motivation, scoping, decision principles.
- [ADR 2026-03-02: Two-Parser Design](../decisions/2026-03-02-two-parser-design.md) — superseded by the above.
- [docs/api/choosing-a-parser.md](../api/choosing-a-parser.md) — rewritten / retired during Stage 5.
- [docs/architecture/pipeline.md](../architecture/pipeline.md) — parse pipeline architecture; affected by the consolidation.
