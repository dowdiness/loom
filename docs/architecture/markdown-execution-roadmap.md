# Markdown Execution Roadmap

**Status:** Active dependency map.
**Related:** [MarkdownIR architecture and target contract](markdown-ir.md), [CommonMark completion handoff](../plans/2026-08-01-commonmark-completion-handoff.md), [#327](https://github.com/dowdiness/loom/issues/327), [#329](https://github.com/dowdiness/loom/issues/329), [#330](https://github.com/dowdiness/loom/issues/330), [#721](https://github.com/dowdiness/loom/issues/721), [#723](https://github.com/dowdiness/loom/issues/723)

---

## Purpose

This document records the execution order for Markdown work that spans editor
projection compatibility, CommonMark block and inline semantics, incremental
hardening, and the independent loomgen lane. It is a dependency map, not a
replacement for the [MarkdownIR architecture contract](markdown-ir.md) or an
issue-by-issue implementation plan.

The order protects two boundaries:

- `Block` / `Inline` remain the editor-facing model until their MarkdownIR
  adapter and projection-identity policy are explicitly established.
- CommonMark conformance work proceeds from shared container and delimiter
  foundations, so later feature slices do not independently invent structural
  or inline semantics.

## M2 — Editor projection compatibility

1. [#341](https://github.com/dowdiness/loom/issues/341) defines the
   MarkdownIR/editor projection identity policy.
2. [#332](https://github.com/dowdiness/loom/issues/332) derives `Block` /
   `Inline` from MarkdownIR while preserving editor, source-map, and edit
   behavior. Loom provides the keyed Block-facing attachment; its separate
   Canopy integration owns the editor commit safe point and teardown.
3. [#425](https://github.com/dowdiness/loom/issues/425) decides the
   editor-facing thematic-break projection after both #341 and #332.

No block or inline milestone may treat MarkdownIR as a replacement for the
editor projection before this chain establishes the adapter boundary.

## M5 — CommonMark block model

1. First make the audit taxonomy completion-grade in
   [#807](https://github.com/dowdiness/loom/issues/807), then establish the
   private Markdown-local block-container decision core in
   [#808](https://github.com/dowdiness/loom/issues/808).
   [#327](https://github.com/dowdiness/loom/issues/327) tracks this foundation;
   it is not itself one broad implementation PR.
2. Once #808 provides that shared model,
   [#474](https://github.com/dowdiness/loom/issues/474) pins parser/lowering
   indentation consistency. List children, indentation, and tabs
   ([#394](https://github.com/dowdiness/loom/issues/394)) follow #474. Work on
   blockquote continuation ([#478](https://github.com/dowdiness/loom/issues/478)),
   indented code ([#392](https://github.com/dowdiness/loom/issues/392)), fenced
   code ([#479](https://github.com/dowdiness/loom/issues/479)), and block
   reference definitions ([#811](https://github.com/dowdiness/loom/issues/811))
   may proceed as independent slices.
3. Complete the residual block work—HTML blocks
   ([#480](https://github.com/dowdiness/loom/issues/480)) and atomic examples
   ([#481](https://github.com/dowdiness/loom/issues/481))—after the shared
   block model is stable. The narrower marker-indent cleanup #460 is superseded
   by #808 rather than layered beside the container core.

## M6 — CommonMark inline model

The following slices can progress in parallel with M5 because they own
independent inline semantics:

- [#483](https://github.com/dowdiness/loom/issues/483) establishes the
  delimiter-run model; [#396](https://github.com/dowdiness/loom/issues/396)
  implements emphasis on that model.
- [#395](https://github.com/dowdiness/loom/issues/395) implements entities.
- [#720](https://github.com/dowdiness/loom/issues/720) implements ordinary-text
  backslash escapes.
- Explicit MarkdownIR nodes distinguish soft breaks, hard-break surface forms,
  autolinks, and inline raw HTML. [#467](https://github.com/dowdiness/loom/issues/467)
  retains the line-break fixture ownership.

Reference definitions remain a block-owned prerequisite. Therefore
[#811](https://github.com/dowdiness/loom/issues/811) owns block recognition and
collection, [#812](https://github.com/dowdiness/loom/issues/812) consumes the
definition table for links/images/references, and
[#397](https://github.com/dowdiness/loom/issues/397) retains category-level
conformance tracking. [#809](https://github.com/dowdiness/loom/issues/809)
owns explicit raw HTML adapter policy and
[#810](https://github.com/dowdiness/loom/issues/810) owns autolink/inline-HTML
semantics.

## M7 — Incremental hardening

[#330](https://github.com/dowdiness/loom/issues/330)'s direct-versus-
incremental parity policy applies within every M5 and M6 slice; it is not a
final-only test pass.

[#721](https://github.com/dowdiness/loom/issues/721) remains narrowly scoped as
the M7 conformance exit audit. It runs after the M5/M6 feature graph and records:

- exact 652/652 CommonMark 0.31.2 HTML equality in explicit passthrough mode;
- clean diagnostics and zero `Unsupported`, malformed `Raw`, or `Recovered`;
- representative direct and incremental parity evidence for every feature family.

Do not add feature-delivery scope to #721. The dedicated tracking issue
[#723](https://github.com/dowdiness/loom/issues/723) is linked from the M2, M5,
M6, M7, and M15 milestone descriptions; #721 remains the conformance gate.

## Independent loomgen lane

The loomgen work is independent of the Markdown dependency chain:

1. M15: [#575](https://github.com/dowdiness/loom/issues/575),
   [#579](https://github.com/dowdiness/loom/issues/579),
   [#529](https://github.com/dowdiness/loom/issues/529), and
   [#556](https://github.com/dowdiness/loom/issues/556), followed by
   [#687](https://github.com/dowdiness/loom/issues/687) and
   [#688](https://github.com/dowdiness/loom/issues/688).
2. M18 → M20 → M21: [#607](https://github.com/dowdiness/loom/issues/607), then
   [#603](https://github.com/dowdiness/loom/issues/603),
   [#560](https://github.com/dowdiness/loom/issues/560), and
   [#614](https://github.com/dowdiness/loom/issues/614), then
   [#689](https://github.com/dowdiness/loom/issues/689) and
   [#608](https://github.com/dowdiness/loom/issues/608).

This lane may ship independently. It must not be represented as a prerequisite
for MarkdownIR editor compatibility or CommonMark conformance.
