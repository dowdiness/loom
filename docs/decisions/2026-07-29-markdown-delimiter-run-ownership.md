# ADR: Keep Markdown Delimiter-Run Resolution Parser-Owned

**Date:** 2026-07-29
**Status:** Proposed
**Issue:** #483
**Related issues:** #329, #332, #396, #772
**Implementation plan:** Issue [#396](https://github.com/dowdiness/loom/issues/396); sequencing is tracked in the [Markdown execution roadmap](../architecture/markdown-execution-roadmap.md)
**Related decisions:** [native-only Markdown inline parsing](2026-07-06-markdown-inline-native-only.md); [MarkdownIR target contract](2026-06-15-markdown-ir-target-contract.md); [MarkdownIR recovery adapter contract](2026-06-17-markdown-ir-recovery-adapter-contract.md); [MarkdownIR performance policy](2026-06-16-markdown-ir-performance-policy.md)

## Context

[CommonMark 0.31.2 emphasis](https://spec.commonmark.org/0.31.2/#emphasis-and-strong-emphasis)
is not a recursive “find the next matching marker” operation. A maximal run
of <code>*</code> or <code>_</code> is classified
from the Unicode characters on both sides, may open, close, or do both, may be
consumed only in part, and participates in the multiple-of-three rule. The
reference parsing strategy records delimiter-run facts and resolves them with a
delimiter stack.

The current Markdown implementation is a smaller speculative subset:

- the lexer emits fixed <code>Star</code> and <code>StarStar</code> tokens and
  treats <code>_</code> as text;
- the inline parser checkpoints at <code>*</code> or <code>**</code>, emits
  <code>BoldNode</code> or <code>ItalicNode</code> when it finds the same fixed
  token, and emits <code>ErrorNode</code> for an unmatched opener;
- direct <code>SyntaxNode -&gt; Block</code> lowering reinterprets some
  escaped-emphasis <code>ErrorNode</code> values with an escaped-opener count;
  and
- <code>SyntaxNode -&gt; MarkdownIR</code> lowering performs a second,
  boolean-like escaped-emphasis normalization alongside its bracket and
  parenthesis recovery.

The lowerings already disagree for valid literal Markdown. For
<code>\*a b**</code>, direct lowering retains <code>**</code> as an error,
while MarkdownIR lowering produces literal text. They also coalesce recovered
list-item text differently. These are useful migration fixtures, but neither
lowering-owned state machine is the durable owner of CommonMark delimiter
semantics.

This decision must preserve the accepted architecture:

- Markdown inline parsing remains hand-authored native code;
- CST remains the lossless syntax and incremental-reuse boundary;
- MarkdownIR remains semantic and must not clone CST token piles or
  parser-only state;
- <code>Recovered</code> and <code>Raw</code> remain explicit for genuine
  recovery; and
- MarkdownIR stays lazy and source origins stay half-open UTF-16 ranges.

## Decision

If accepted, CommonMark delimiter-run resolution belongs to a private,
Markdown parser-local module. A deterministic core computes a resolution plan
from one inline container, and the parser shell emits that plan as lossless
CST. Lowerings consume the resulting CST; they do not classify flanking,
maintain a delimiter stack, or reinterpret valid unmatched delimiters.
The CST records the resolved concrete parse structure; it does not become the
owner of transform semantics. MarkdownIR remains the typed semantic and
transform layer described by the accepted target contract.

~~~text
inline-container token facts
        |
        v
delimiter resolution core
State + Event -> (State, Decision)
        |
        v
parser CST emission
        |
        +--> direct Block adapter (temporary compatibility path)
        |
        +--> MarkdownIR --> Block / mdast / HTML / rewrite adapters
~~~

The state, event, decision, delimiter-stack representation, and any local
mutation are private implementation details. They must not mention
<code>SyntaxNode</code>, <code>Inline</code>, or <code>MarkdownIR</code>.
Local mutation is acceptable while building a returned resolution plan,
provided it has no observable external effect.

### CST contract

The resolver and parser must produce source-ordered, non-crossing CST:

- matched delimiter characters are owned by nested <code>ItalicNode</code> and
  <code>BoldNode</code> ranges;
- escaped, unmatched, or unused portions of a delimiter run remain literal
  CST tokens, not <code>ErrorNode</code> values and not diagnostics;
- CST token kind or shape must distinguish characters consumed as emphasis
  boundaries from marker-shaped literal content inside an emphasis node.
  Parent node kind alone is insufficient: CommonMark
  [example 412](https://spec.commonmark.org/0.31.2/#example-412) parses the inner
  <code>**</code> in <code>*foo**bar*</code> as literal text;
- code spans form opaque inline events; links form bounded events with the
  CommonMark delimiter-stack scope needed for nested label emphasis;
- genuine lexer or parser errors remain explicit recovery nodes and are never
  reinterpreted as emphasis; and
- resolver state is created per inline container and never crosses that
  container, source revision, or parser session. A link label introduces a
  scoped stack bottom rather than a reset: outer delimiter state remains
  available across the link, while label-owned delimiter searches cannot
  escape their CommonMark boundary.

The Markdown package's <code>Token</code> and <code>SyntaxKind</code> variants
are exported, so their variants and observed token or CST shape are not private
implementation details. This proposal does not authorize changing that
surface. #396 must include an explicit compatibility review before changing
it. That review must also cover how both <code>*</code> and <code>_</code>
receive exact editable roles without classifying every marker-shaped token
under <code>BoldNode</code> or <code>ItalicNode</code> as a delimiter.

One-character <code>*</code> and <code>_</code> lexer facts are the leading
implementation candidate because the current parser event API consumes a
whole lexer token and CommonMark can consume only part of a run. Existing
variants and raw syntax-kind IDs must not be removed or reused. If #396 changes
which exported tokens are emitted or changes CST shape, it must document that
as an intentional compatibility change and update the relevant contract and
snapshot tests. A different private fact adapter is acceptable only if it can
emit exact partial-run source ranges without a new public Loom parser API.

### MarkdownIR contract

Delimiter runs are not first-class MarkdownIR nodes.

| Source result | MarkdownIR result | Origin contract |
| --- | --- | --- |
| matched one-character delimiters | <code>Italic(children, content_origin)</code> | full <code>origin</code> includes both consumed delimiters; <code>content_origin</code> is the exact raw interior |
| matched two-character delimiters | <code>Bold(children, content_origin)</code> | full <code>origin</code> includes both consumed delimiter pairs; <code>content_origin</code> is the exact raw interior |
| nested or ambiguous runs | nested or sibling <code>Italic</code>, <code>Bold</code>, and <code>Text</code> selected by CommonMark order | origins are nested or disjoint and never cross |
| escaped delimiter | ordinary <code>Text</code> after backslash unescaping | origin includes the raw escape and delimiter spelling |
| unmatched or unused run portion | ordinary <code>Text</code> | CST retains the exact residual-token range; MarkdownIR may coalesce contiguous text while retaining a source-covering origin |
| genuine malformed recovery | <code>Recovered</code> or <code>Raw</code> | diagnostic and source-origin behavior stays governed by the recovery adapter contract |

For an emphasis node with a <code>content_origin</code>, source-preserving
consumers can recover the opening spelling from
<code>source[origin.start:content_origin.start]</code> and the closing spelling
from <code>source[content_origin.end:origin.end]</code>. No public delimiter
token array, marker enum, run length, or delimiter-stack metadata is added to
MarkdownIR. Canonical formatting may choose canonical <code>*</code> or
<code>**</code> spelling; preserve and local rewrite modes use the source and
origins when spelling fidelity matters.

Adjacent <code>Text</code> segmentation is not delimiter semantics. Exact
editable delimiter roles continue to come from CST token spans, but only when
the concrete shape identifies consumed boundary characters separately from
residual literal characters. MarkdownIR and its adapters preserve semantic
text and source coverage; they do not infer editable roles from parent kind.

### Incremental and performance contract

The first implementation may conservatively invalidate and resolve the whole
affected inline container. It must not claim run-local invalidation.

For each container and revision:

- token and run visits are bounded linearly by container size;
- resolver state and plans are discarded when the container or revision
  changes;
- no lowering adds a sibling rescan, eager second source reconstruction, or
  persistent delimiter cache; and
- one-shot, incremental, and block-reparse paths produce the same CST,
  diagnostics, MarkdownIR, and target output.

A cache or generic token cursor requires separate evidence and review. The
deferred delimiter-frontier investigation is not an integration-ready API.

### Migration and issue #772

The preferred delimiter-work order remains #483, then #396:

1. keep the current direct and MarkdownIR differences as named
   characterization evidence;
2. implement parser-local delimiter resolution in #396, promoting official
   CommonMark fixtures by rule cluster;
3. make direct and MarkdownIR lowering mechanical projections of the same CST;
4. remove the escaped-emphasis lowering state machines made obsolete by that
   parser-owned resolution.

That work order does not make the number or landing order of an issue the
trigger for #772. Re-audit #772 at the first merged change that materially
alters its caller topology:

- #332, if it retires the active direct <code>SyntaxNode -&gt; Block</code>
  adapter; or
- #396, if parser-owned delimiter resolution removes lowering-owned recovery
  policy.

Landing either issue without the corresponding topology change does not settle
#772. At the re-audit, inventory the active adapters. Extract the smallest
private reducer only if at least two independent active adapters still require
the same transition policy. If fewer than two callers remain, close #772 as
superseded instead of preserving a transitional abstraction.

Until that topology changes, keep the recovery differences as named
characterization evidence and do not introduce #772's shared lowering reducer.

In particular, the current direct path's escaped-opener count is
characterization evidence, not the CommonMark oracle. A backslash-escaped
opener and an otherwise unmatched trailing run are valid literal Markdown.

## Rationale

Parser ownership keeps all delimiter decisions at the component that already
owns inline-container boundaries, code-span precedence, CST events, and
incremental invalidation. A pure resolution core keeps the difficult algorithm
deterministic and testable, while the imperative parser shell remains
responsible for CST emission.

Emitting resolved concrete CST nodes avoids introducing a second
resolved-inline tree between CST and MarkdownIR. The CST records parser output
and lossless source structure, while MarkdownIR remains the semantic owner and
shared transform input. This preserves the lowering seams around
<code>BoldNode</code> and <code>ItalicNode</code> without sending parser
machinery into MarkdownIR, consistent with its anti-CST-cloning contract.

The full-origin plus content-origin pair is sufficient for source-preserving
rewrites without public delimiter metadata. Adding marker and run fields would
duplicate source facts that CST and the source string already own.

## Alternatives considered

### Put delimiter runs in public MarkdownIR

Rejected. It would expose transient parser-stack facts, make every adapter
understand unresolved syntax, and move MarkdownIR toward a CST clone.

### Resolve raw delimiter CST independently in each lowering

Rejected. It recreates the drift already visible between direct and MarkdownIR
recovery and makes target adapters responsible for parsing.

### Add a second private resolved-inline tree between CST and all adapters

Not selected. It centralizes semantics, but duplicates the semantic tree and
requires multiple adapters. A parser-local plan that emits the existing
resolved concrete CST has a smaller migration surface and keeps one lossless
syntax truth.

### Share the current escaped-emphasis recovery reducer first

Deferred. It would reduce short-term duplication but entrench a workaround for
the current speculative parser. #396 is expected to make valid escaped and
unmatched delimiters ordinary literal syntax, potentially deleting every
caller.

## Verification

Acceptance of this decision does not itself implement #396. Implementation
must include:

- table-driven pure resolver tests for Unicode flanking, <code>*</code> and
  <code>_</code>, odd and even escapes, partial consumption, the
  multiple-of-three rule, nesting, links, code spans, and literal fallback;
- source-origin tests for opening and closing spellings, nested nodes, residual
  run portions, escapes, and local rewrites;
- CST role fixtures that distinguish consumed markers from residual literal
  markers, including CommonMark example 412, and cover both <code>*</code> and
  <code>_</code>;
- direct-vs-MarkdownIR Block parity for the supported compatibility surface,
  with any temporary representation difference named explicitly;
- existing diagnostic-override and <code>Recovered</code> and
  <code>Raw</code> tests;
- official CommonMark 0.31.2 fixture promotion in #396 rather than in this
  decision change;
- full-vs-incremental and block-reparse parity for delimiter-boundary edits;
  and
- paired release benchmarks for direct and MarkdownIR lowering on both normal
  and recovery-heavy documents, plus a linear-scaling delimiter workload.

The characterization surface for this proposal lives in
[escaped_emphasis_recovery_test.mbt](../../examples/markdown/escaped_emphasis_recovery_test.mbt).
The paired recovery-heavy lowering rows live in
[recovery_benchmark_test.mbt](../../examples/markdown/recovery_benchmark_test.mbt).
They are ungated characterization rows in this proposal, not yet frozen
baseline or PR-guard inputs. #396 may promote them to the base/head guard only
after the same workload exists on both comparison revisions and its target
semantics are accepted.

## Consequences

- #483 requires maintainer approval before #396 changes production CST.
- This proposal adds no public code API. #396 separately reviews any change to
  the exported Markdown token stream or CST shape.
- #396 will intentionally change valid unmatched delimiter output from error
  recovery to literal text where the current subset is non-conforming.
- Exact source spelling remains available through CST and origins without
  making delimiter runs semantic IR nodes.
- Direct <code>Block</code> lowering remains a temporary compatibility adapter
  until #332 derives it from MarkdownIR.
- #772 stays open during the proposal and is re-audited when #332 or #396
  materially changes its caller topology; issue landing order alone is not the
  trigger. This ADR does not close or silently redefine it.

## Approval requested

Maintainers must explicitly decide:

1. whether delimiter resolution is parser-owned and MarkdownIR remains
   semantic-only;
2. whether full origin plus exact content origin is sufficient without public
   delimiter metadata;
3. whether #772 is re-audited on a material caller-topology change and a shared
   reducer requires at least two independent active adapters, as recommended;
4. whether #396 may intentionally change the exported Markdown token or CST
   behavior needed for partial delimiter-run consumption and exact
   delimiter-versus-literal roles.
