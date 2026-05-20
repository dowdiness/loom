# ADR: Lambda Rename Consumer

**Date:** 2026-05-20
**Status:** Accepted
**Implementation plan:** [docs/archive/completed-phases/2026-05-19-rename-consumer-plan.md](../archive/completed-phases/2026-05-19-rename-consumer-plan.md)
**Spec:** [docs/archive/completed-phases/2026-05-19-rename-consumer-design.md](../archive/completed-phases/2026-05-19-rename-consumer-design.md)

## Context

The Tier 1+ callers projection shipped `CallersPipeline::visible_from` for
rename and conflict-detection consumers. That API answers whether a name is
visible from a scope, but it deliberately does not expose binding identity or
offset-keyed lookup. Rename planning needs both, plus all raw call facts rather
than the stricter `callers_of` view.

## Decision

Ship the lambda rename consumer as a new `examples/lambda/src/rename/` package
with a one-shot public entry point:

```moonbit
plan_rename(pipeline, source, syntax, offset, new_name) -> RenamePlan
```

Extend `CallersPipeline` with one accessor, `facts()`, returning defensive
copies of cached `(defs, calls, enclosing)` facts. The rename package reads
those facts once, locates the binding by identifier-token range, computes
`TextEdit`s, and emits structured `@core.Diagnostic` values for no-target,
no-op, sibling collision, capture, and shadow cases.

The rename package does not add new `@incr` cells. It consumes the existing
callers pipeline state as a single-revision query.

Expose `DiagnosticLabel::DiagnosticLabel(range, message)` from
`dowdiness/loom/core` so external packages can construct labeled structured
diagnostics without relying on private record construction.

## Rationale

Keeping rename in its own package preserves the callers package as a fact and
visibility provider. The only callers API expansion is the raw facts accessor
needed by consumers that must reason about binding identity and all references.

The conflict checks stay client-side because `visible_from` is intentionally a
membership query. The rename consumer reconstructs innermost binding behavior
from `defs` and `enclosing`, and uses conservative two-pass capture detection
over defs and calls. Conservative false positives are acceptable for editor
review; false negatives would permit unsafe edits.

Top-level references are filtered with the lambda module's sequential,
non-recursive binding semantics: a top-level definition is visible only after
its full `LetDef` range ends. A reference inside `let f = ...` is not treated as
bound to that same `f`; a later top-level definition of the same name shadows it
only after the later definition is complete.

Structured diagnostics keep editor integration data-rich: consumers can inspect
codes, severity, primary ranges, and labels rather than parsing strings.

## Consequences

Editor consumers can build rename previews from `RenamePlan.edits` and decide
whether to apply them based on diagnostic severity.

The implementation inherits the current callers extractor limitations: lexical
scope modeling is lambda/let-paren based, curried let-paren nesting is deferred,
top-level recursion is not modeled, and facts are scoped to one parser
revision.

Future rename work should add UI integration or broaden language semantics in
separate follow-up plans. It should not move this logic into Datalog until the
incremental relation layer supports retraction across revisions.
