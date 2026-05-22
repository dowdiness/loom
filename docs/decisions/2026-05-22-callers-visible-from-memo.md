# ADR: Callers `visible_from` Memo Projection

**Date:** 2026-05-22
**Status:** Accepted
**Implementation plan:** [docs/archive/completed-phases/2026-05-19-callers-visible-from-plan.md](../archive/completed-phases/2026-05-19-callers-visible-from-plan.md)
**Spec:** [docs/archive/completed-phases/2026-05-19-callers-visible-from.md](../archive/completed-phases/2026-05-19-callers-visible-from.md)

## Context

The lambda callers projection already exposed scope-aware facts for definitions
and call sites. Rename and conflict-detection consumers needed one additional
query: whether a candidate name is visible from a modeled scope.

The original escalation question was whether the second scope consumer should
move callers facts into `@incr` Datalog. Investigation found that the current
relation engine is insert-only across revisions: without retraction, structural
facts would leak after edits and make visibility queries stale.

## Decision

Expose `CallersPipeline::visible_from(scope, name) -> Bool` as a pure Memo over
the current parser revision.

The extraction pass emits enclosing-scope edges alongside definitions and
calls. `build_visibility` folds those facts into a flat
`HashMap[(ScopeId, String), Unit]`, and the pipeline anchors the facts,
callers index, and visibility map with persistent observers.

Do not model this projection with Datalog until the relation layer supports
retraction across revisions.

## Rationale

The Memo recomputes from the current syntax tree and cannot retain facts from
older revisions. That matches the editor workflow and avoids false positives
from deleted or renamed bindings.

The visibility query is a membership test, not a binding-resolution API. It is
enough for conservative conflict detection, while consumers that need exact
binding identity can read raw callers facts through the separate accessor added
for the rename package.

Keeping Datalog out of this slice also avoids adding relation plumbing whose
main promised benefit is unavailable until retract support exists.

## Consequences

`visible_from` is part of the callers package public API. Future callers
consumers can use it for conservative scope-membership checks, but should not
treat it as innermost-binding resolution or shadow analysis.

The rename consumer remains a one-shot package over callers facts. It should
not move to Datalog until the relation engine can remove stale facts between
parser revisions.

When retract support lands, revisit the archived spec's Datalog analysis before
building a structural-facts relation layer.
