# ADR: Markdown Inline Parsing Stays `@native` (Out of loomgen Generation Scope)

**Date:** 2026-07-06
**Status:** Accepted
**Issues:** [#642](https://github.com/dowdiness/loom/issues/642), [#608](https://github.com/dowdiness/loom/issues/608)

loomgen targets the CommonMark **block** subset as a generation goal, but
CommonMark **inline** parsing (emphasis, links, inline code) stays permanently
hand-authored `@native` host code and is **not** a loomgen generation target.
This ADR records that scope boundary and the conditions under which it would be
revisited.

## Context

The M16–M21 EBNF roadmap makes the CommonMark block subset a loomgen generation
target. Its capstone, [#608](https://github.com/dowdiness/loom/issues/608)
(Markdown block parser, M21), wires `@fragment` + `@native` + `#loom.void` +
`Pred::HostGuard` together with M20's `@speculative` / `SeparatedList` / `~>` /
`@error_node` to generate the block grammar. That issue's scope line is explicit:

> Out-of-scope: inline parsing and the CommonMark inline specification.

Inline parsing in the hand-written example (`examples/markdown/inline_parser.mbt`)
is imperative:

- speculative `ctx.checkpoint()` / `ctx.restore()` delimiter matching for
  bold / italic / inline-code / link (L112–235), re-emitting unclosed openers as
  literal text;
- balanced-paren depth counting for link destinations
  (`let mut depth = 1` … `while depth > 0`, L242–248).

It is reached from the block grammar via `@native` inline dispatch. The current
example is already narrower than full CommonMark inline — it has no
flanking-based emphasis precedence and no link reference definitions.

Before this ADR, nothing recorded whether loomgen should *ever* generate inline,
or whether `@native` is the permanent answer. The boundary was implied only by
#608's scope line. This ADR makes it a recorded decision.

## Decision

**Markdown inline parsing stays permanently `@native` host code. loomgen does
NOT target CommonMark inline generation.**

The sanctioned pattern for inline in generated grammars is `@native` inline
dispatch (with `Pred::HostGuard` where a host predicate is needed) invoked from
the generated block grammar. #608's block scope is unaffected and remains the
loomgen target.

## Rationale

Inline CommonMark is not expressible as a reified `@grammar.GrammarIr` value,
which by invariant carries only data — "data tested with `Pred::matches`, never
host closures" (`loom/grammar/interpreter.mbt:84`), with `derive(Eq, Debug)` on
the IR enums.

1. **Emphasis is not context-free.** CommonMark "process emphasis" is a
   delimiter-stack algorithm with run-length bookkeeping and left-/right-flanking
   rules. It needs mutable stack state a `derive(Eq, Debug)` `Pred` cannot carry
   — the same constraint that made [#541](https://github.com/dowdiness/loom/issues/541)
   reject `Custom(fn)` in favor of the `Native(RuleName)` escape hatch.
2. **Link reference definitions are document-global and two-pass.** They need a
   reference map collected across the whole document before inline resolution —
   not something a local, position-independent grammar node can express.
3. **Balanced-paren link destinations** need depth counting, again mutable state
   outside the reified predicate vocabulary.

Forcing these into the IR would reintroduce host closures and break
`derive(Eq, Debug)` on the IR — a cost the roadmap already declined once (#541).
Keeping inline as `@native` preserves the IR's data-only invariant while still
letting the block grammar be generated.

## Consequences

- `examples/markdown/inline_parser.mbt` stays hand-written; no "generate Markdown
  inline" capstone or tracking issue will be created.
- `@native` inline dispatch (+ `Pred::HostGuard`) is the **documented, permanent**
  pattern for inline in generated grammars — not a temporary workaround.
- loomgen's advertised reach for Markdown is precisely: **block structure
  generated, inline delegated to host code.** Docs (loomgen `README.md`
  limitations) must state this so the boundary is not mistaken for an unfinished
  feature.
- No change to any parser signature, `.mbti`, or generated interface follows from
  this ADR; it is a scope decision plus documentation.

## Revisit condition

This is a **won't-generate** decision, not a deferral. Reopen only if **either**:

- (a) a **second** language independently needs generated inline delimiter
  matching (emphasis-like runs), establishing a real reuse case for a first-class
  primitive — Markdown alone does not qualify; or
- (b) someone designs a reified delimiter-stack / flanking primitive that
  preserves `derive(Eq, Debug)` on `GrammarIr` (no host closures).

## Alternatives considered

- **A reified inline-delimiter primitive in `GrammarIr`.** Rejected: would carry
  mutable stack / flanking state, breaking the data-only IR invariant — the exact
  tradeoff #541 already declined with `Custom(fn)`.
- **Generate inline via a second `SwitchLexMode` / lexer-pull pass.** Rejected for
  inline: mode switching (M19) addresses lexical context, not the delimiter-stack
  and document-global reference-map algorithms that inline resolution requires.
- **Leave the boundary implicit in #608's scope line.** Rejected: an unrecorded
  "out-of-scope" reads as an unfinished feature; a decision record makes the
  won't-generate stance and its revisit rule explicit.
