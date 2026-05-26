---
name: loom
description: Use when writing or reviewing MoonBit code that constructs a parser against the `dowdiness/loom` framework — calling `new_parser`, `Parser::new`, `apply_edit`, `set_source`, or extracting derived projections from a syntax tree. Catches the recurring mistake of constructing `@incremental.ImperativeParser` directly inside a Derived, which discards all incremental state.
---

# loom

Reference for the canonical `@loom` parser-construction surface. Adapt
to context — these are patterns the project consistently uses, not
enforcement rules.

Citation paths in this skill are repo-relative to **this repo**
(`dowdiness/loom`) unless explicitly qualified with a sister repo
(`dowdiness/canopy: …` for the umbrella monorepo's docs). The `loom`
parser-framework package itself lives at `loom/src/`; the lambda
example at `examples/lambda/`.

## When to Use

Trigger keywords: `@loom.new_parser`, `@loom.Parser`,
`@incremental.ImperativeParser`, `apply_edit`, `set_source`,
`syntax_tree`, `parser.runtime()`, `Grammar`, `@lambda.lambda_grammar`,
or any code building a parser inside a reactive closure.

Sister skill: **incr** — for the GC anchor and inside-vs-outside read
conventions that downstream pipelines attached to a parser need.

## The Big One: Don't Reach Past `Parser[Ast]`

`@incremental.ImperativeParser` is the low-level engine.
`@loom.Parser[Ast]` is the unified wrapper that owns one engine and
publishes its state as `@incr.Input` / `@incr.Derived` cells so
downstream consumers can subscribe.

**Constructing `@incremental.ImperativeParser::new` inside a Derived body
throws away all incremental state on every re-eval.** Every recompute
allocates a fresh engine and full-parses from scratch — defeating the
entire point of an incremental parser. The unified `Parser[Ast]` owns
the engine across re-evals and only the engine's *output* flows
through the reactive graph.

```moonbit
// ❌ Allocates a new ImperativeParser on every recompute.
//    Full parse each time. No incremental reuse possible.
let bad_derived = scope.derived(fn() {
  let p = @incremental.ImperativeParser::new(source_input.get(), lang)
  p.parse().syntax
})

// ✅ Engine lives outside the reactive graph; views are Derived cells.
let parser = @loom.new_parser(initial_source, grammar)
let syntax = parser.syntax_tree()    // -> Derived[@seam.SyntaxNode]
let derived = scope.derived(
  fn() { extract_facts(syntax.get_or_abort()) },
  label="facts",
)
// To advance: parser.apply_edit(edit, new_source) or
//             parser.set_source(new_source).
```

**Don't call `@incremental.ImperativeParser::new` directly in user
code.** The two sanctioned entry points are:

- `@loom.new_parser(source, grammar, runtime?)` — the default. Use this
  for every reactive / attached pipeline AND for one-shot tests where
  you'd otherwise want a throwaway parser. The reactive wrapping cost is
  not interesting in a test, and the call site stays liftable into a
  real reactive context without rewiring.
- `@loom.new_imperative_parser(source, grammar)` — use only when you
  intentionally want to exercise or benchmark the raw `ImperativeParser`
  engine surface (engine fuzz tests, differential tests against the
  unified parser, performance probes targeting the engine).

## Quick Reference

| Goal | Call | Notes |
|------|------|-------|
| Build a unified, incr-integrated parser | `@loom.new_parser(source, grammar, runtime?)` | Returns `@loom.Parser[Ast]`. Pass `runtime~` to join an existing graph; omit for a fresh `Runtime` owned by the parser. |
| Build the raw engine (rarely needed in user code) | `@loom.new_imperative_parser(source, grammar)` | Engine-targeted tests / differential probes only — not a general "skip the wrapper" escape hatch. |
| Get the reactive source text view | `parser.source()` | `-> @incr.Derived[String]` |
| Get the reactive syntax tree view | `parser.syntax_tree()` | `-> @incr.Derived[@seam.SyntaxNode]` |
| Get the reactive AST view | `parser.ast()` | `-> @incr.Derived[Ast]` |
| Get the reactive diagnostics view | `parser.diagnostics()` | `-> @incr.Derived[@core.DiagnosticSet]` |
| Get the full snapshot view | `parser.snapshot()` | `-> @incr.Derived[ParseSnapshot[Ast]]` |
| Advance the parser | `parser.apply_edit(...)` or `parser.set_source(...)` | See `parser.mbt` for signatures and the engine semantics. |
| Reach the underlying `Runtime` | `parser.runtime()` | Use to root a `Scope` for downstream attachments. |
| One-shot parse in a test | `let p = @loom.new_parser(s, g); p.syntax_tree().read_or_abort()` | Throwaway parser is fine when you don't need to advance it. |

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

JSON and Markdown examples follow the same shape — each exposes a
public `<lang>_grammar` value.

## Attaching Downstream Pipelines

When deriving a pipeline from a parser, share its runtime so the
dependency graph stays connected, and follow the
**incr** skill's GC-anchor template (`Scope` + persistent `Watch` +
`dispose`).

```moonbit
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

Canonical reference: `examples/lambda/src/typed_parser.mbt` and
`examples/lambda/src/callers/callers.mbt`.

## One-Shot Parsing (Tests, Pure Extraction)

For tests or helpers that just need to parse a string and walk the
tree once, a throwaway `@loom.new_parser` followed by `read_or_abort()`
is idiomatic — you don't have to construct an `ImperativeParser`
manually.

```moonbit
test "extract callers from snippet" {
  let parser = @loom.new_parser(source, @lambda.lambda_grammar)
  let syntax = parser.syntax_tree().read_or_abort()
  let (defs, calls) = extract_facts(syntax)
  // ... assertions
}
```

Why this over `@incremental.ImperativeParser::new` + `parse()`: you
get the same syntax tree, fewer raw-API touchpoints, and the helper
can be lifted into a real reactive context later without rewiring.

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `@incremental.ImperativeParser::new` inside `scope.derived(fn () { ... })` | Every recompute does a full parse; "incremental" is theatre | Hoist the parser out, expose `parser.syntax_tree()`, use `.get_or_abort()` inside the Derived |
| Building a new `Runtime` for a downstream pipeline rooted on a parser | Two disconnected graphs; gc/batch don't reach the parser's interior cells | Use `parser.runtime()` to share |

## Red Flags — Pause and Verify

- About to write `@incremental.ImperativeParser` anywhere in user code
  that isn't the loom framework itself → reach for `@loom.new_parser`
  or `@loom.new_imperative_parser` instead.
- Building a parser inside a `scope.derived` closure → stop, hoist it.
- New `Runtime::new()` in code that already has a parser in scope →
  use `parser.runtime()` instead.

## Canonical Files to Cite (Verify Before Asserting)

- `loom/src/pipeline/parser.mbt` — `Parser[Ast]` definition; every
  public method this skill mentions lives here.
- `loom/src/factories.mbt:230` — `new_parser` signature.
  `new_imperative_parser` is just above.
- `loom/src/factories.mbt:212` — `new_imperative_parser` signature.
- `examples/lambda/src/typed_parser.mbt` — canonical parser-attached
  pipeline (Scope + Watch + dispose).
- `examples/lambda/src/callers/callers.mbt` — second example, uses
  every loom + incr pattern this skill covers.
- `CLAUDE.md` — package map, ADR pointer for the unified parser (ADR
  2026-04-17), and Stage 6 history.

If any file has moved, update the skill — paths drift faster than the
patterns do.

## Related Memories

- `feedback_api_misuse_pattern.md` — names the specific
  `ImperativeParser`-in-Derived miss this skill exists to prevent.
- `project_parser_unification_research.md` — ADR + migration history
  for the unified `Parser[Ast]`.
- `project_callers_prototype.md` — Tier 0 projection built correctly
  against `Parser[Ast]`.

## Out of Scope

- The `seam` CST API (`@seam.SyntaxNode`, `@seam.CstNode`, traversal
  primitives). Those have their own conventions and aren't covered
  here — see `seam/` directly.
- Defining a new language. See
  `dowdiness/canopy: docs/development/ADDING_A_LANGUAGE.md` for the
  dedicated walkthrough (the umbrella monorepo's docs, not this repo).
