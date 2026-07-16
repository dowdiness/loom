# Markdown Execution Roadmap

**Status:** Active dependency map.
**Related:** [MarkdownIR architecture and target contract](markdown-ir.md), [#327](https://github.com/dowdiness/loom/issues/327), [#329](https://github.com/dowdiness/loom/issues/329), [#330](https://github.com/dowdiness/loom/issues/330), [#721](https://github.com/dowdiness/loom/issues/721), [#723](https://github.com/dowdiness/loom/issues/723)

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
   behavior.
3. [#425](https://github.com/dowdiness/loom/issues/425) decides the
   editor-facing thematic-break projection after both #341 and #332.

No block or inline milestone may treat MarkdownIR as a replacement for the
editor projection before this chain establishes the adapter boundary.

## M5 — CommonMark block model

1. [#327](https://github.com/dowdiness/loom/issues/327) establishes the
   container/block parser and MarkdownIR flow-content foundation.
2. Once #327 provides that shared model, work on list children and indentation
   ([#394](https://github.com/dowdiness/loom/issues/394)), blockquote
   continuation ([#478](https://github.com/dowdiness/loom/issues/478)),
   indented code ([#392](https://github.com/dowdiness/loom/issues/392)), fenced
   code ([#479](https://github.com/dowdiness/loom/issues/479)), and block
   reference definitions ([#482](https://github.com/dowdiness/loom/issues/482))
   may proceed as independent slices.
3. Complete the residual block work—setext/thematic-break interaction
   ([#430](https://github.com/dowdiness/loom/issues/430)), marker-indentation
   consolidation ([#460](https://github.com/dowdiness/loom/issues/460)),
   parser/lowering indentation consistency
   ([#474](https://github.com/dowdiness/loom/issues/474)), HTML blocks
   ([#480](https://github.com/dowdiness/loom/issues/480)), and atomic examples
   ([#481](https://github.com/dowdiness/loom/issues/481))—after the shared
   block model is stable.

## M6 — CommonMark inline model

The following slices can progress in parallel with M5 because they own
independent inline semantics:

- [#483](https://github.com/dowdiness/loom/issues/483) establishes the
  delimiter-run model; [#396](https://github.com/dowdiness/loom/issues/396)
  implements emphasis on that model.
- [#395](https://github.com/dowdiness/loom/issues/395) implements entities.
- [#720](https://github.com/dowdiness/loom/issues/720) implements ordinary-text
  backslash escapes.
- [#485](https://github.com/dowdiness/loom/issues/485) establishes line-break
  semantics and [#467](https://github.com/dowdiness/loom/issues/467) adds the
  corresponding fixtures.
- [#487](https://github.com/dowdiness/loom/issues/487) implements autolinks and
  inline raw HTML.

Reference definitions remain a block-owned prerequisite. Therefore
[#486](https://github.com/dowdiness/loom/issues/486) follows M5 #482, and
[#397](https://github.com/dowdiness/loom/issues/397) follows both #482 and
#486 for document-level reference/link resolution.

## M7 — Incremental hardening

[#330](https://github.com/dowdiness/loom/issues/330)'s direct-versus-
incremental parity policy applies within every M5 and M6 slice; it is not a
final-only test pass.

[#721](https://github.com/dowdiness/loom/issues/721) remains narrowly scoped as
the M7 conformance exit audit. It runs after #327, #329, and #330 and records:

- the full CommonMark audit and 326/652 comparison;
- ownership for every residual failure; and
- representative direct and incremental parity evidence.

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
