# Markdown Projection Identity Implementation Plan

**Status:** Complete

**Completion:** Implemented by [PR #724](https://github.com/dowdiness/loom/pull/724), merged 2026-07-16; closes [#341](https://github.com/dowdiness/loom/issues/341).

Decision record:

- ADR: [Markdown projection identity boundary](../../decisions/2026-07-15-markdown-projection-identity-boundary.md).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish tested, domain-owned Markdown editor identity across MarkdownIR projections without treating `ProjNode` IDs, paths, or source offsets as durable identity.

**Architecture:** Add a Markdown-local identity adapter after MarkdownIR lowering. It extracts deterministically ordered semantic anchors and typed keys, previews the complete leaf set through Loom's generic `ProjectionIdentityTracker`, applies only collision-safe local surface-normalized overrides, and commits one combined full baseline. `Block` / `Inline`, `ProjNode`, and `SourceMap` remain view-local consumers.

**Tech Stack:** MoonBit; `examples/markdown`; `loom/projection`; `@core.Edit`; existing `ProjectionIdentityTracker`.

## Global Constraints

- Preserve the public `Block` / `Inline` model and all current parser entry points.
- Do not change generic `ProjectionIdentityTracker`, `ProjNode`, `SourceMap`, or parser-core APIs.
- Identity baseline data is only `{anchor, typed semantic key, MarkdownNodeId}`; view paths are rebuilt and never persisted.
- Encode typed keys injectively into `ProjectionLeaf.key`; do not use source text, `kind_tag()`, paths, or offsets as identity keys.
- Use MarkdownIR preorder with role ordering `block payload`, `inline container`, `scalar payload` for equal anchor starts.
- Raw, recovered, and unsupported nodes never produce durable Markdown IDs.
- Payload edits receive fresh IDs; #341 preserves identity only for unchanged semantic payload under surface-only rewrites.
- Every behavioral change follows TDD: write and observe a failing focused test before production code.

---

### Task 1: Define Markdown identity leaves and deterministic extraction

**Files:**
- Create: `examples/markdown/markdown_projection_identity.mbt`
- Create: `examples/markdown/markdown_projection_identity_wbtest.mbt`
- Modify: `examples/markdown/markdown_ir.mbt`
- Modify: `examples/markdown/markdown_ir_lowering.mbt`
- Modify: `examples/markdown/markdown_ir_test.mbt`
- Modify: `examples/markdown/moon.pkg`

**Interfaces:**
- Consumes: `MarkdownIR::origin`, `content_origin`, `destination_origin`, new `label_origin`, lowered inline children, `kind_tag`, recovery predicates, and `@projection.ProjectionLeaf`.
- Produces: `MarkdownIR::label_origin() -> MarkdownIROrigin?`; private typed Markdown identity-key variants; a normalized link-label child fingerprint; deterministic extraction of identity leaves in preorder; an opaque `MarkdownNodeId` representation for the adapter.

- [ ] Write failing MarkdownIR tests for simple and formatted link labels: the lowering records the contiguous range between brackets as `label_origin`, while structurally discontinuous labels return `None`.
- [ ] Run `rtk moon test examples/markdown --filter "MarkdownIR:*link*"` and observe failure because `label_origin` is absent.
- [ ] Extend `MarkdownIRNode::Link`, its constructor, public accessor, and lowering so `label_origin` is extracted from the bracket-delimited CST range only when contiguous; update existing Link pattern matches and adapter tests.
- [ ] Implement private key variants and injective component-length-prefixed encoding into `ProjectionLeaf.key`.
- [ ] Implement extraction as MarkdownIR preorder: emit a current editor-facing leaf, then children in MarkdownIR child order; equal-start roles order block payload, inline container, scalar payload.
- [ ] Implement no leaf for nodes without a safe contiguous semantic origin; never substitute a whole node origin.
- [ ] Re-run the focused tests. Expected: all anchor, omission, encoding, and ordering cases pass.
- [ ] Run `rtk moon check`.
- [ ] Commit: `feat(markdown): extract projection identity leaves`.

### Task 2: Implement recovery-safe alignment and attachment output

**Files:**
- Modify: `examples/markdown/markdown_projection_identity.mbt`
- Modify: `examples/markdown/markdown_projection_identity_wbtest.mbt`

**Interfaces:**
- Consumes: the full previous `ProjectionIdentityTracker` baseline, extracted full next-leaf sequence, optional `@core.Edit`, and a domain allocator seeded from all baseline IDs.
- Produces: a complete stable Markdown identity sequence plus an ephemeral mapping from `MarkdownNodeId` to the current `Block` / `Inline` attachment; one successful tracker commit.

- [ ] Write failing tests for a one-transaction ATX-to-setext replacement, bullet-marker spelling replacement, fence-character replacement, formatted-link-label rewrite (`[plain](url)` to `[*plain*](url)`) retaining identity, label text rewrite (`[plain](url)` to `[changed](url)`) resetting identity, heading-depth change, code-language change, heading payload change, link-destination change, duplicate sibling reorder, and nested equal-range extraction.
- [ ] Write failing malformed-round-trip tests proving the adapter records failed input, does not allocate an error-node ID, and uses the tracker's pending recovery path on the next successful projection.
- [ ] Run the focused test file. Expected: identity alignment API is absent or behavior fails.
- [ ] Implement local one-to-one candidate matching only for equal typed classes, matched context, unique ordered correspondence, and identical semantic anchor payload; for link labels compare a normalized lowered-child fingerprint that erases only `Bold`/`Italic` wrappers and preserves child order, text and inline-code values, hard breaks, and nested-link destinations rather than raw `label_origin` bytes.
- [ ] Preview the complete next leaf set through `ProjectionIdentityTracker::realign_success_with_optional_edit`; do not call the free realignment helper on filtered baselines.
- [ ] Apply a local override only when its old ID is absent from every other preview position. Verify one leaf per next index and unique IDs. On verification failure, retain the unmodified generic preview.
- [ ] Call `ProjectionIdentityTracker::commit_success` once with the selected complete stable sequence. Keep view attachment paths outside the baseline and rebuild them every success.
- [ ] Re-run focused tests. Expected: all surface, semantic, recovery, collision, and ordering cases pass.
- [ ] Run `rtk moon check` and `rtk moon test examples/markdown`.
- [ ] Commit: `feat(markdown): align projection identities safely`.

### Task 3: Prove editor-view separation and document the live adapter boundary

**Files:**
- Modify: `examples/markdown/markdown_projection_identity_wbtest.mbt`
- Modify: `examples/markdown/README.mbt.md`
- Modify: `docs/architecture/markdown-ir.md`
- Modify: `docs/README.md`

**Interfaces:**
- Consumes: stable results from the Markdown identity adapter and existing `Block` / `Inline` projection traits.
- Produces: behavior proof that durable Markdown IDs survive view rebuilds while paths and `ProjNode` IDs remain non-durable; architecture documentation matching implementation.

- [ ] Write a failing test that rebuilds the current Markdown view for unchanged semantic input and proves a stable `MarkdownNodeId` can remain equal while its view-local attachment/path differs.
- [ ] Run the focused test. Expected: missing attachment API or failing separation assertion.
- [ ] Implement the smallest adapter result/accessor needed to expose durable ID-to-current-view association without adding IDs to `Block`, `Inline`, MarkdownIR, `ProjNode`, or `SourceMap`.
- [ ] Update Markdown documentation to state the implemented #341 identity policy, payload-edit non-goal, recovery behavior, and `ProjNode` view-local rule. Update the docs index for any new Markdown documentation.
- [ ] Re-run the focused test, `rtk moon test examples/markdown`, `rtk moon check`, and `rtk ./check-docs.sh`.
- [ ] Run `rtk moon info`; review generated interfaces and confirm no accidental public constructor or `Block` / `Inline` API change.
- [ ] Commit: `docs(markdown): document projection identity boundary`.

### Task 4: Final contract verification

**Files:**
- Modify only files required by verification fixes.

**Interfaces:**
- Consumes: the complete adapter, focused identity tests, Markdown parser tests, and documentation.
- Produces: evidence that #341 is ready to unblock #332 without changing editor projection ownership.

- [ ] Run the complete `rtk moon test` suite.
- [ ] Run `rtk moon check --target all`.
- [ ] Run `rtk ./check-docs.sh`.
- [ ] Inspect `moon info` generated-interface changes and reject unexpected public API drift.
- [ ] Review each required behavior against the approved design: surface-only continuity; selected semantic resets; raw/recovered exclusion; malformed recovery; view-local `ProjNode`; duplicate/reorder safety; nested ordering.
- [ ] Commit any necessary test/documentation-only verification corrections separately from implementation commits.
- [ ] Apply the documentation protocol closure decision: create or update an ADR because #341 establishes a reusable projection-identity policy; link it from `docs/README.md`, record the plan/issue rationale, and run `rtk ./check-docs.sh`.

## Plan Self-Review

- **Spec coverage:** Tasks 1–2 cover anchor/key extraction, deterministic ordering, full-preview composition, recovery, collision safety, and all identity semantics. Task 3 covers the required view-local proof and documentation. Task 4 validates the complete contract.
- **Placeholder scan:** No placeholder implementation decisions remain; each task names the responsible files, APIs, behavior, and commands.
- **Type consistency:** The Markdown-local adapter owns typed keys and opaque IDs; generic Loom receives encoded `ProjectionLeaf.key` values and full arrays only; `Block` / `Inline` remain unchanged.
