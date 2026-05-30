---
name: loom
description: Use when writing or reviewing MoonBit code against the `dowdiness/loom` framework — constructing parsers with `new_parser`, updating `Parser` via `apply_edit`/`set_source`, attaching downstream `@incr.Derived` pipelines to `parser.runtime()`, or preserving semantic projection IDs with `ProjectionIdentityBaseline` / `ProjectionIdentityTracker`. Catches recurring mistakes such as constructing `@incremental.ImperativeParser` inside a reactive closure or advancing projection identity baselines before semantic lowering succeeds.
---

# loom

Reference for the canonical `@loom` parser-construction and authoring-projection
surface. Adapt to context — these are patterns the project consistently uses,
not enforcement rules.

Citation paths in this skill are repo-relative to **this repo**
(`dowdiness/loom`) unless explicitly qualified with a sister repo
(`dowdiness/canopy: …` for the umbrella monorepo's docs). The `loom`
parser-framework package itself lives at `loom/src/`; the lambda example at
`examples/lambda/`.

## When to Use

Parser/reactive triggers: `@loom.new_parser`, `@loom.Parser`,
`@incremental.ImperativeParser`, `apply_edit`, `set_source`, `syntax_tree`,
`parser.runtime()`, `Grammar`, `<lang>_grammar`, or any code building a parser
inside a reactive closure.

Projection-identity triggers: `ProjectionIdentityBaseline`,
`ProjectionIdentityTracker`, `ProjectionLeaf`, `StableProjectionLeaf`,
`ProjectionStringIdAllocator`, `realign_projection_identities`,
`realign_projection_items`, stable IDs, last-good semantic projection, malformed
input recovery, or pending baseline-relative edits.

Sister skill: **incr** — for the GC anchor / `.get_or_abort()` vs
`.read_or_abort()` conventions that downstream pipelines attached to a parser
need.

## The Big One: Don't Reach Past `Parser[Ast]`

`@incremental.ImperativeParser` is the low-level engine. `@loom.Parser[Ast]` is
the unified wrapper that owns one engine and publishes its state as read-only
`@incr.Derived` views (`source`, `syntax_tree`, `ast`, `diagnostics`,
`snapshot`) so downstream consumers can subscribe.

**Constructing `@incremental.ImperativeParser::new` inside a Derived/Memo body
throws away all incremental state on every re-eval.** Every recompute allocates
a fresh engine and full-parses from scratch — defeating the entire point of an
incremental parser. The unified `Parser[Ast]` owns the engine across re-evals
and only the engine's *output* flows through the reactive graph.

```moonbit
// ❌ Allocates a new ImperativeParser on every recompute.
//    Full parse each time. No incremental reuse possible.
let bad = scope.derived(fn() {
  let p = @incremental.ImperativeParser::new(source_input.get(), lang)
  p.parse().syntax
})

// ✅ Engine lives outside the reactive graph; views are Derived cells.
let parser = @loom.new_parser(initial_source, grammar)
let syntax = parser.syntax_tree()    // -> @incr.Derived[@seam.SyntaxNode]
let derived = scope.derived(
  fn() { extract_facts(syntax.get_or_abort()) },
  label="facts",
)
// To advance: parser.apply_edit(edit, new_source) or
//             parser.set_source(new_source).
```

**Don't call `@incremental.ImperativeParser::new` directly in user code.** The
two sanctioned entry points are:

- `@loom.new_parser(source, grammar, runtime?)` — the default. Use this for every
  reactive / attached pipeline AND for one-shot tests where you would otherwise
  want a throwaway parser. The reactive wrapping cost is not interesting in a
  test, and the call site stays liftable into a real reactive context without
  rewiring.
- `@loom.new_imperative_parser(source, grammar)` — use only when you
  intentionally need the non-reactive engine without the input/derived layer:
  engine fuzz tests, differential tests against the unified parser, performance
  probes targeting the engine, one-shot batch tools, or subsystems that own
  their own runtime lifecycle and cannot accept a caller-supplied `Runtime`.

## Quick Reference

| Goal | Call | Notes |
|------|------|-------|
| Build a unified, incr-integrated parser | `@loom.new_parser(source, grammar, runtime?)` | Returns `@loom.Parser[Ast]`. `Ast : Eq`; grammar tokens must satisfy the factory bounds. Pass `runtime~` to join an existing graph; omit for a fresh `Runtime` owned by the parser. |
| Build the raw engine (rarely needed in user code) | `@loom.new_imperative_parser(source, grammar)` | Intentional non-reactive engine cases only: engine tests/probes, batch tools, or runtime-lifecycle constraints — not a general "skip the wrapper" escape hatch. |
| Get the reactive source text view | `parser.source()` | `-> @incr.Derived[String]` |
| Get the reactive syntax tree view | `parser.syntax_tree()` | `-> @incr.Derived[@seam.SyntaxNode]` |
| Get the reactive AST view | `parser.ast()` | `-> @incr.Derived[Ast]`; current recovered AST, not a last-good semantic document. |
| Get the reactive diagnostics view | `parser.diagnostics()` | `-> @incr.Derived[@core.DiagnosticSet]` |
| Get the full snapshot view | `parser.snapshot()` | `-> @incr.Derived[ParseSnapshot[Ast]]` |
| Advance the parser incrementally | `parser.apply_edit(edit, new_source)` | Uses CST-node-level reuse through the engine; publishes one coherent snapshot inside `Runtime::batch`. |
| Replace source wholesale | `parser.set_source(new_source)` | Full reparse, discards incremental state; identical source is a no-op. |
| Reach the underlying `Runtime` | `parser.runtime()` | Use to root a `Scope` for downstream attachments. |
| One-shot parse in a test | `let p = @loom.new_parser(s, g); p.syntax_tree().read_or_abort()` | Throwaway parser is fine when you don't need to advance it. Prefer direct `Derived::read_or_abort()` over legacy `rt.read(...)`. |

## Grammar Reference (Lambda Example)

The lambda example exposes a public grammar handle:

```moonbit
let parser = @loom.new_parser(source, @lambda.lambda_grammar)
let typed = attach_typecheck(parser)
let callers = CallersPipeline::CallersPipeline(
  parser.runtime(),
  parser.syntax_tree(),
)
```

JSON and Markdown examples follow the same shape — each exposes a public
`<lang>_grammar` value.

## Attaching Downstream Pipelines

When deriving a pipeline from a parser, share its runtime so the dependency
graph stays connected, and follow the **incr** skill's GC-anchor template
(`Scope` + persistent `Watch` + `dispose`).

```moonbit
pub(all) struct MyAttachment {
  scope : @incr.Scope
  watch : @incr.Watch[Result]
}

pub fn attach_my_thing(
  parser : @loom.Parser[@ast.Term],
) -> MyAttachment {
  let rt = parser.runtime()                  // ← share the runtime
  let scope = @incr.Scope::new(rt)
  let derived = scope.derived(
    fn() { do_work(parser.syntax_tree().get_or_abort()) },
    label="derived",
  )
  let watch = scope.add_watch(derived.watch())
  { scope, watch }
}
```

Inside a `scope.derived` closure, read parser views with `.get_or_abort()` (or
`.get()` if graceful cycle handling is intentional). Outside the graph, use
`.read_or_abort()` or a persistent `Watch`. Do not call `rt.read(...)` inside a
tracked closure.

Canonical references: `examples/lambda/src/typed_parser.mbt` and
`examples/lambda/src/callers/callers.mbt`.

## One-Shot Parsing (Tests, Pure Extraction)

For tests or helpers that just need to parse a string and walk the tree once, a
throwaway `@loom.new_parser` followed by `read_or_abort()` is idiomatic — you
don't have to construct an `ImperativeParser` manually.

```moonbit
test "extract callers from snippet" {
  let parser = @loom.new_parser(source, @lambda.lambda_grammar)
  let syntax = parser.syntax_tree().read_or_abort()
  let (defs, calls) = extract_facts(syntax)
  // ... assertions
}
```

Why this over `@incremental.ImperativeParser::new` + `parse()`: you get the same
syntax tree, fewer raw-API touchpoints, and the helper can be lifted into a real
reactive context later without rewiring.

## Stable Projection Identity Helpers

Use these when a semantic/authoring projection has public leaf IDs that should
survive edits and malformed intermediate input. Loom supplies the reusable
identity alignment policy; downstream code still owns the semantic document,
projection diagnostics, public ID type, and allocator.

### Direct success path

Keep a `ProjectionIdentityBaseline[Id]` with the last successful semantic
document. After parse diagnostics are clear and projection/lowering succeeds,
realign new leaves and commit a new baseline. Allocation is a downstream callback
so any public ID type can be used:

```moonbit
let leaves = extract_projection_leaves(syntax)
let next_baseline = old_baseline.advance(
  current_source,
  leaves,
  allocate_id,
  edit=editor_edit,
)
```

For string IDs specifically, `ProjectionStringIdAllocator::from_baseline` is the
common convenience. It only accepts `ProjectionIdentityBaseline[String]`:

```moonbit
let allocator = @loom.ProjectionStringIdAllocator::from_baseline(
  old_string_baseline,
  make_public_id,
)
let next_baseline = old_string_baseline.advance(
  current_source,
  leaves,
  fn(leaf) { allocator.allocate(leaf) },
  edit=editor_edit,
)
```

If you already have domain items, use `@loom.realign_projection_items` /
`realign_projection_items_with_optional_edit` to extract leaves and zip IDs back
onto caller-owned item shapes.

### Malformed-input recovery path

Use `ProjectionIdentityTracker[Id]` when you want Loom to own the last-good
identity baseline plus pending failed-input edit/fallback state.

```moonbit
let tracker = @loom.ProjectionIdentityTracker::from_baseline(old_baseline)

// Parser diagnostics, projection failure, or lowering failure: retain the
// baseline and record the current input. Exact edits must be relative to the
// current last-good baseline; invalid/non-baseline edits degrade to source-diff
// fallback.
tracker.record_failed_input(
  malformed_source,
  source_before_edit=old_baseline.source(),
  edit=editor_edit,
)

// Later, after parse + projection produce candidate leaves, preview alignment.
let stable = tracker.realign_success(
  recovered_source,
  recovered_leaves,
  allocate_id,
)

// Only after semantic lowering succeeds:
tracker.commit_success(recovered_source, stable)
```

Rules:

- `realign_success` is preview-only. It must not be treated as commit.
- `commit_success` is the only tracker operation that advances the retained
  baseline and clears pending failed-input state.
- If there is no baseline yet, `realign_success` allocates IDs for every leaf;
  then `commit_success` can seed the first baseline.
- Multiple distinct failed inputs, `set_source`, missing `source_before_edit`,
  non-baseline source, source mismatch, or invalid edit coordinates should fall
  back to source diffing rather than pretending an exact edit is still valid.
- Allocation remains delegated to downstream ID code; `ProjectionStringIdAllocator`
  is only the common string-ID convenience and requires `Id == String`.

## Current Diagnostics vs Last-Good Semantics

`parser.source()`, `parser.syntax_tree()`, `parser.ast()`, and
`parser.diagnostics()` are **current parse state** and advance on every parser
update. A last-good semantic document is downstream state. Gate semantic
projection on parser diagnostics plus projection/lowering success; do not make
`parser.ast()` stand in for a last-good semantic model.

If current input is parser-invalid or projection-invalid, publish diagnostics for
the current text, retain the last-good semantic document/baseline, and only
advance identity state on a later successful projection.

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `@incremental.ImperativeParser::new` inside `scope.derived(fn() { ... })` / `scope.memo(...)` | Every recompute does a full parse; "incremental" is theatre | Hoist the parser out, expose `parser.syntax_tree()`, use `.get_or_abort()` inside the Derived |
| Building a new `Runtime` for a downstream pipeline rooted on a parser | Two disconnected graphs; gc/batch don't reach the parser's interior cells | Use `parser.runtime()` to share |
| Reading parser views with `rt.read(...)` inside a Derived body | One-shot observer overhead and wrong read semantics | Use `.get_or_abort()` inside tracked closures |
| Storing a downstream Derived without a persistent Watch/Observer | `Runtime::gc()` can sweep the chain | Store a `Scope` and `Watch`; dispose the scope explicitly |
| Calling `ProjectionIdentityTracker::commit_success` after parse success but before projection/lowering success | Failed semantic lowering can replace the last-good baseline | Treat `realign_success` as preview; commit only after the semantic document is trusted |
| Passing parser-current edits after malformed input as if they were baseline-relative | Identity churn or wrong prefix/suffix reuse | Use `record_failed_input`; exact edits must be relative to the last-good baseline, otherwise fall back to source diff |

## Red Flags — Pause and Verify

- About to write `@incremental.ImperativeParser` anywhere in user code that isn't
  the loom framework itself → reach for `@loom.new_parser` or
  `@loom.new_imperative_parser` instead.
- Building a parser inside a `scope.derived` / `scope.memo` closure → stop,
  hoist it.
- New `Runtime::new()` in code that already has a parser in scope → use
  `parser.runtime()` instead.
- About to read `parser.ast()` for a semantic layer that must gate on diagnostics
  or retain last-good state → use `parser.syntax_tree()` + diagnostics gating.
- About to advance `ProjectionIdentityBaseline` / call `commit_success` on a
  failed parse, failed projection, or failed lowering path → retain last-good
  state instead.
- About to implement custom prefix/suffix projection-ID realignment downstream →
  check `ProjectionIdentityBaseline`, `ProjectionIdentityTracker`, and
  `realign_projection_items` first.

## Canonical Files to Cite (Verify Before Asserting)

- `loom/src/pipeline/parser.mbt` — `Parser[Ast]` definition; public parser
  methods return `@incr.Derived` views and updates batch one coherent snapshot.
- `loom/src/factories.mbt:231` — `new_parser` signature.
  `new_imperative_parser` is just above.
- `loom/src/factories.mbt:213` — `new_imperative_parser` signature.
- `loom/src/core/projection_identity.mbt` — `ProjectionLeaf`,
  `StableProjectionLeaf`, `ProjectionIdentityBaseline`,
  `ProjectionIdentityTracker`, `ProjectionStringIdAllocator`, and realignment
  helpers.
- `docs/api/projection-guide.md#stable-identity-across-edits` — public guidance
  for baseline/tracker use.
- `docs/api/last-good-semantic-attachment.md` — state policy for current parser
  diagnostics plus retained last-good semantic documents.
- `docs/api/api-contract.md#projection-identity-helpers` — API stability table.
- `docs/decisions/2026-05-29-stable-semantic-projection-identity.md` — ADR for
  stable projection identity and tracker follow-up (#177).
- `examples/lambda/src/typed_parser.mbt` — canonical parser-attached pipeline
  (`Scope` + `Derived` + `Watch` + `dispose`).
- `examples/lambda/src/callers/callers.mbt` — second parser-attached pipeline and
  source-projection example.
- `CLAUDE.md` — package map, ADR pointer for the unified parser (ADR
  2026-04-17), and Stage 6 history.

If any file has moved, update the skill — paths drift faster than the patterns
do.

## Related Memories

- `feedback_api_misuse_pattern.md` — names the specific
  `ImperativeParser`-in-Memo miss this skill exists to prevent.
- `project_parser_unification_research.md` — ADR + migration history for the
  unified `Parser[Ast]`.
- `project_callers_prototype.md` — Tier 0 projection built correctly against
  `Parser[Ast]`.
- `project_loom_incremental_reuse_contract.md` — parser/CST reuse contract and
  API-hardening history.

## Out of Scope

- The lower-level `seam` CST storage/event API (`@seam.CstNode`, `CstToken`,
  `EventBuffer`, source-span backing strings, parser-owned reuse rebase hooks).
  Projection code may use `@seam.SyntaxNode` navigation, but source-span/event
  details have their own conventions — read `seam/` docs/API before changing
  them.
- Defining a new language. See
  `dowdiness/canopy: docs/development/ADDING_A_LANGUAGE.md` for the dedicated
  walkthrough (the umbrella monorepo's docs, not this repo).
