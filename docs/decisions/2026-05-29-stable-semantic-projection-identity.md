# ADR: Stable Semantic Projection Identity Helper

**Date:** 2026-05-29
**Status:** Accepted
**Issue:** [#162](https://github.com/dowdiness/loom/issues/162)
**Follow-ups:** [#177](https://github.com/dowdiness/loom/issues/177),
[#178](https://github.com/dowdiness/loom/issues/178)
**Guide:** [CST Projection Guide](../api/projection-guide.md#stable-identity-across-edits)

## Context

Authoring projections often lower a CST into a semantic document with public,
domain-owned IDs. CST reuse and source spans are not enough to keep those IDs
stable: duplicate tokens can shift, unchanged suffix leaves move after
insertions/deletions, and malformed intermediate text can recover after the
parser baseline has advanced.

Downstream projects need a reusable policy that is not tied to a specific
language. They also need to keep their own public ID shape instead of exposing
Loom parser or CST IDs.

## Decision

Add a small authoring projection helper to `dowdiness/loom/core` and re-export
it through `@loom`:

- `ProjectionLeaf` records a projected user-facing leaf's source range and
  domain-owned key.
- `StableProjectionLeaf[Id]` pairs a projected leaf with a generic public ID.
- `ProjectionIdentityBaseline[Id]` stores the last successful semantic source
  plus stable leaves.
- `ProjectionIdentityTracker[Id]` owns the reusable identity baseline plus a
  pending failed-input edit/fallback marker for authoring facades that do not
  want to hand-roll last-good identity state. Its realignment step is
  preview-only; committing remains explicit so semantic lowering can fail
  without advancing the baseline.
- `realign_projection_identities` / `ProjectionIdentityBaseline::advance`
  preserve matching prefix/suffix IDs around an editor `Edit` or source-diff
  fallback window and call a projection-owned allocator only for changed-window
  leaves or key mismatches.
- `ProjectionStringIdAllocator` provides the common seeded string-ID allocator
  pattern while still taking a caller-supplied ID formatter.
- `realign_projection_items` adapts domain items by extracting leaves and
  zipping the resulting IDs back onto caller-owned item shapes.

The helper is intentionally leaf-level and language-neutral. It does not attach
IDs to syntax tokens or CST nodes, and it does not impose any concrete public ID
format.

## Rationale

The stable-ID problem belongs at the authoring projection boundary: only the
projection knows which leaves are user-facing and which ID shape is public.
Loom can still provide the reusable edit-window alignment policy so downstream
projects do not each reimplement prefix/suffix preservation and recovery
fallbacks.

Keeping the last-good source and stable leaves together gives malformed-input
recovery the baseline it needs. Accepting an exact editor edit when available
preserves precise damage windows; falling back to a minimal source diff keeps
`set_source` and recovery paths usable when no baseline-relative edit exists.

## Consequences

Authoring integrations that need stable semantic IDs should retain a
`ProjectionIdentityBaseline` with their last-good semantic document. On the next
successful projection, they should extract `ProjectionLeaf` values in source
order and advance the baseline with a domain allocator. String-ID projections can
seed `ProjectionStringIdAllocator` from the retained baseline so newly allocated
IDs skip IDs that were preserved in the reusable prefix/suffix.

Parser and CST APIs remain unchanged. The helpers are conservative: they do not
reuse IDs inside the changed window, and they allocate fresh IDs if a prefix or
suffix leaf's key unexpectedly differs. `ProjectionIdentityTracker` deliberately
tracks only identity baselines and pending edit/fallback state; parser
diagnostics, projection diagnostics, semantic documents, and lowering results
remain language-owned.
