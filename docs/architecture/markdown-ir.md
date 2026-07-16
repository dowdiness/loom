# MarkdownIR: Architecture and Target Contract

**Status:** Accepted M0 target contract and closeout policy.
**Related:** [#323](https://github.com/dowdiness/loom/issues/323), [#331](https://github.com/dowdiness/loom/issues/331), [#337](https://github.com/dowdiness/loom/issues/337), [#340](https://github.com/dowdiness/loom/issues/340), [#335](https://github.com/dowdiness/loom/issues/335), [#336](https://github.com/dowdiness/loom/issues/336)

---

## Purpose

MarkdownIR is the planned semantic and transform layer for Loom's Markdown
example. It is not a block-reparse API change. The Markdown block-reparse fast
paths proved conservative incremental parsing for the current CST and
`Block`/`Inline` path; MarkdownIR addresses a different problem: one typed layer
that can feed editor projection, mdast export, CommonMark HTML conformance,
source-preserving rewrites, and a canonical formatter without making any target
view the basement representation.

Target shape:

```text
Source text
  -> Lexer / parser
  -> CST / SyntaxNode + diagnostics
  -> MarkdownIR
  -> target views and backends
       - Block / Inline editor projection model
       - mdast / unist JSON export
       - CommonMark HTML renderer and fixture harness
       - source-preserving rewrite backend
       - canonical formatter backend
```

`Block` / `Inline` remains the editor-facing projection model. It is not legacy
and must not be replaced in place. mdast compatibility is an export and
conformance target over MarkdownIR, not the internal ideal.

---

## Responsibility boundaries

| Layer | Owns | Does not own |
|---|---|---|
| CST / `SyntaxNode` | Lossless concrete syntax, token/trivia fidelity, parser diagnostics, recovered parser structure, UTF-16 source positions, incremental reuse and block-reparse correctness. | Markdown semantic truth, transform policy, editor projection identity, mdast field naming, or safe HTML policy. |
| MarkdownIR | Typed semantic tree, source origins, optional content origins, explicit diagnostics/recovery nodes, and selected transform-relevant surface metadata. It is the shared input for transforms and target adapters. | Arbitrary CST token arrays, all whitespace/trivia, parser scaffolding, editor-specific payload shape, mdast-as-internal-shape, or standalone byte-for-byte source reconstruction without the original source/CST. |
| `Block` / `Inline` | Editor-facing Markdown model used by projection traits, `ProjNode`, `SourceMap`, edit operations, and `SyncEditor` integration. It should stay small and convenient for the block editor. | CommonMark completeness, mdast compatibility, canonical formatting, full source preservation, or future transform semantics. |
| mdast / unist JSON | Interchange/export shape for the JavaScript Markdown ecosystem, including optional unist positions converted at the adapter boundary. | Internal representation, parser correctness proof, editor model, or source-preservation mechanism. |
| HTML | Rendering behavior and CommonMark conformance oracle. The HTML backend is a target adapter with an explicit raw-HTML safety mode. | Definition of MarkdownIR shape or mdast compatibility. |

Current public surfaces stay valid while MarkdownIR is introduced:

- `markdown_grammar` continues to be the parser integration surface initially.
- `parse`, `parse_markdown`, and `parse_cst` keep their current behavior until a
  deliberate migration changes them.
- `markdown_fold_node` may remain the direct `SyntaxNode -> Block` algebra until
  the `SyntaxNode -> MarkdownIR -> Block/Inline` adapter is proven.
- Canopy's Markdown projection memos currently consume `@markdown.Block`; the
  target migration is additive:

  ```text
  current: SyntaxNode -> Block/Inline -> ProjNode[Block] -> SourceMap/edit ops
  target:  SyntaxNode -> MarkdownIR -> Block/Inline -> ProjNode[Block] -> SourceMap/edit ops
  ```

`LanguageSpec` and block-reparse APIs are parser contracts, not MarkdownIR
contracts. MarkdownIR lowering may reuse existing parser and fold APIs, but M0
does not add parser-core API surface.

### Projection identity boundary

MarkdownIR owns a private, typed identity adapter for semantic leaves. It uses
content origins as anchors, injectively encoded semantic keys, and Loom's
`ProjectionIdentityTracker` to preserve IDs through surface-only rewrites while
retaining the last successful baseline across malformed input. Raw, recovered,
and unsupported nodes have no durable Markdown identity.

Surface spelling can preserve an unchanged payload ID: ATX/setext headings,
unordered-list marker spelling, and fenced-code delimiter character or width.
Heading depth, list semantics, code language, payload text, and link
destination changes receive a fresh ID. Link-label formatting preserves its
identity only when the lowered child fingerprint is unchanged.
Local overrides require a unique match on typed key, matched parent context,
and semantic payload. Duplicate siblings remain ambiguous: they and descendants
without a matched parent receive fresh IDs rather than retaining a generic
preview ID.

The durable ID sequence is intentionally independent of `Block` / `Inline`
paths, `ProjNode` allocations, and `SourceMap` ranges. No Markdown
`ProjNode`/`SourceMap` constructor exists in this repository; the
Canopy-owned compatibility path remains the only owner of the current
ID-to-view attachment. That later integration must rebuild an ephemeral mapping
from the current projection and must not persist a path, source offset, or
`ProjNode` ID in the Markdown identity baseline.

---

## Anti-CST-cloning rule

MarkdownIR is:

```text
semantic tree + source origins + selected transform-relevant surface metadata
```

MarkdownIR is not:

```text
semantic tree + every CST token + every trivia/whitespace detail
```

A proposed IR field must fit one of these buckets:

1. **Semantic field:** belongs in MarkdownIR. Examples: heading depth, list kind,
   ordered-list start, list/item spread, code info/value, link destination/title.
2. **Transform-relevant surface metadata:** belongs in a small node-specific
   surface record or enum. Examples: ATX vs setext heading, unordered marker
   spelling, ordered delimiter, fence character/count, indentation shape needed
   by a list/container transform.
3. **Exact source trivia:** remains in CST/source text. MarkdownIR stores an
   origin span and consumers slice the original source when exact preservation is
   required.
4. **Malformed or unsupported input:** becomes an explicit `Recovered` or `Raw`
   IR node with origin and diagnostics, while genuinely unsupported known syntax
   remains `Unsupported`. It must not become a token pile on otherwise semantic
   nodes.
5. **Target-only data:** stays in the adapter for mdast, HTML, or the editor if
   it is not core semantic or transform-relevant data.

Reject designs with generic `tokens`, `children_tokens`, all-trivia arrays, or
APIs that require target adapters to inspect raw token lists to understand a
semantic node.

Origins are references back to source/CST, not a second copy of the document.
Internal origins use Loom's UTF-16 code-unit offsets; line/column and unist
position objects are export-boundary conversions.

---

## MarkdownIR invariants

Future MarkdownIR implementations must preserve these invariants before target
adapters see a value. They are part of the semantic contract, not optional test
fixtures.

### Origin and range invariants

- Every source-backed IR node has a full source origin: a half-open UTF-16 range
  that covers the concrete syntax responsible for that node.
- Nodes may also carry narrower content origins for editable semantic payloads,
  such as heading text, list item content, code contents, or link labels. Content
  origins must stay inside the full node origin.
- Parent origins contain child origins. Sibling origins in the same child list are
  source-ordered and non-overlapping. Recovery nodes may model overlap or
  zero-width synthesis only when that fact is explicit in the recovery shape and
  diagnostics.
- Origins identify where to slice the original source/CST. They do not imply that
  MarkdownIR owns enough text to reconstruct unchanged source by itself.
- Line/column positions, mdast/unist positions, browser offsets, and editor tree
  positions are adapter conversions from these internal UTF-16 ranges.

### Tree-shape invariants

- A document contains flow/block content. Inline content only appears inside
  inline-bearing block nodes or inline containers.
- Container blocks contain flow/block children. List items are flow containers;
  they are not restricted to inline-only payloads, even while the current editor
  projection model stays smaller.
- Child order is source order. Semantic canonicalization may merge equivalent
  surface spellings, but it must not reorder author content.
- Diagnostics and recovery are explicit nodes or side records. Target adapters
  must never infer malformed input from missing required semantic fields.

### Semantic-node invariants

- Heading depth is validated as CommonMark heading depth `1..6`. Heading surface
  form is separate from heading semantics.
- Lists distinguish semantic kind from surface marker spelling. Ordered lists
  carry validated start/order information; list tightness or spread is semantic
  because it changes rendered structure.
- Code blocks distinguish info-string language, metadata, literal value, and
  surface form. The value excludes fence markers and boundary newlines; fence
  marker spelling and width are surface metadata.
- Links and images distinguish destination, title, label/text, and inline versus
  reference form where supported. Reference resolution policy belongs to the
  document-level lowering contract, not to target adapters guessing from raw
  tokens.
- Raw HTML, unsupported extensions, and malformed regions use explicit raw or
  recovered nodes with origins and diagnostics. They must not be represented as
  token arrays attached to otherwise semantic nodes.

### Surface-metadata invariants

- Surface metadata is node-specific and typed. It records choices needed for
  transforms, such as heading form, list marker spelling, ordered delimiter,
  fence character/count, or container indentation shape.
- Surface metadata is optional unless a transform needs it. A missing surface
  value means the adapter should choose a canonical or target-specific spelling,
  not inspect raw token piles.
- Different surface spellings may share the same semantic shape. Tests for new
  IR features should prove this by comparing semantics while preserving distinct
  surface metadata.
- Arbitrary whitespace, comments of no semantic relevance, newline trivia, and
  untouched marker spelling that no transform needs remain in CST/source slices.

---

## CST lowering boundary

The CST-to-MarkdownIR boundary is a lowering adapter from `SyntaxNode` to the
semantic tree. It may inspect CST node kinds, token text, and source ranges to
extract semantic and transform-relevant facts, but its output is typed IR plus
origins, not a copied token stream.

Implementation guidance for future PRs:

- Reuse the existing memoized CST fold shape for `SyntaxNode -> IR` when the IR
  is derived from the whole syntax tree **and the IR is position-independent**.
  `CstFold` keys its cache by structural hash and returns cached results
  verbatim, so an IR that bakes absolute source origins into its values will
  return stale origins after position-shifting edits. MarkdownIR stores absolute
  origins and therefore lowers from the live `SyntaxNode` without `CstFold` at
  M1. The fold boundary still applies to position-independent targets such as
  the current `Block`/`Inline` editor model.
- Reparse tiny surface facts from token text when the CST no longer carries a
  typed token payload, as the current Markdown fold does for heading depth and
  code info. Store the result as validated semantic/surface data, not as the
  token itself.
- Keep `LanguageSpec`, lexer/parser recovery, and block-reparse APIs parser-side.
  MarkdownIR lowering may consume their outputs but should not add parser-core
  hooks for transform policy.
- Keep `SourceMap` and `ProjNode` concerns adapter-side. Editor source maps can
  be derived from IR origins plus the `Block`/`Inline` projection path; they are
  not the MarkdownIR storage format.
- Preserve current `Block` / `Inline` APIs until an explicit compatibility PR
  changes them. MarkdownIR feeds that editor projection model; it does not
  replace it in place.

---

## API migration and compatibility plan

Migration is additive until an explicit compatibility PR says otherwise.

Compatibility floor:

- `parse(source) -> Block` remains the tolerant high-level parser. Lex failures
  still fold to `Block::Error`, and recovered parser structure still lowers to
  the current editor model.
- `parse_markdown(source) -> (Block, @core.DiagnosticSet) raise @core.LexError`
  remains the diagnostics-returning high-level path over the current
  `Block` / `Inline` projection. Lexical-error inputs still raise; parser
  recovery diagnostics stay in the returned diagnostic set.
- `parse_cst(source) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError`
  remains the CST entry point. Lexical-error inputs still raise. It must not
  start returning MarkdownIR or hiding parser diagnostics.
- `markdown_spec` remains the Markdown `LanguageSpec`; `LanguageSpec`,
  lexer/recovery choices, and block-reparse configuration stay parser-side.
- `markdown_grammar` remains `Grammar[Token, SyntaxKind, Block]` initially, so
  `new_parser` / `new_imperative_parser` keep publishing `Block` as their AST
  view. A separate IR grammar is not part of M0; introduce one only for a real
  consumer that needs a parser AST view of MarkdownIR and after explaining why
  `parse_cst` plus lowering, `CstFold`, or `Grammar::to_syntax_grammar` is not
  enough.
- `markdown_fold_node` remains the public `CstFold` algebra for
  `SyntaxNode -> Block`. Its implementation may later delegate through
  MarkdownIR, but the signature and `Block` / `Inline` semantics stay pinned
  until compatibility tests are intentionally changed.

New MarkdownIR surfaces:

- First IR lowering, parser, export, render, rewrite, or formatter entry points
  must be additive and explicitly labeled experimental or stable in docs and
  generated interfaces.
- Compatibility tests must pin the existing `parse` / `parse_markdown` /
  `parse_cst` / `markdown_grammar` behavior, including the LexError-raising
  signatures for `parse_markdown` and `parse_cst`, before any migration changes
  those surfaces.
- Canopy integration stays `SyncEditor[@markdown.Block]` through
  `lang/markdown/companion` and `ProjNode[@markdown.Block]` / `SourceMap`
  projection memos until a compatibility PR deliberately changes that contract.
  The target migration is an internal pipeline swap from
  `SyntaxNode -> Block/Inline` to `SyntaxNode -> MarkdownIR -> Block/Inline`,
  not a requirement that editor code consume MarkdownIR directly.
- Public API PRs must run `moon info` and review `.mbti` diffs for signatures,
  visibility, constructors, trait bounds, and adapter leakage. A docs-only PR or
  a PR with no public MoonBit changes should say that no generated-interface
  diff is expected.

---

## Canonicalization and formatting vocabulary

Use these terms consistently:

- **Semantic canonicalization:** different concrete syntaxes lower to the same
  semantic IR shape when they mean the same thing. It normalizes surface choices;
  it must not erase fields that affect rendered structure or transform meaning.
- **Surface preservation:** selected syntax choices remain attached as typed,
  node-specific metadata when transforms need them. Heading form, list marker
  spelling, ordered-list delimiter, and code-fence character/count are surface
  metadata; arbitrary whitespace is not promoted unless a transform needs it.
- **Preserve-mode rewrite:** unchanged IR nodes reuse original source slices via
  origins. MarkdownIR alone is not expected to print byte-for-byte source.
- **Local transform rewrite:** changed nodes render from IR, using semantic fields
  plus relevant surface metadata, while unchanged surrounding ranges are sliced
  from the original source.
- **Canonical formatter mode:** a target backend that intentionally ignores
  existing surface style and emits normalized Markdown. Canonical formatting is
  not the definition of MarkdownIR.

### Canonicalization examples

These sketches are contract examples, not final type names. Future tests should
compare semantic equality separately from surface-metadata equality and include
boundary cases where surface spelling affects block segmentation.

- **ATX vs setext headings.** `# Title` and `Title\n=====` both lower to a
  heading with `depth=1` and inline text `Title`. The surface record keeps the
  heading form (`atx` or `setext`) and the relevant marker/content origins.
  Preserve/local rewrites can keep the author's form; canonical formatting may
  choose one normalized heading style.
- **Unordered list markers.** `- item` and `* item` both lower to the same
  semantic unordered list and item content when considered as standalone lists or
  items in one list segment. The surface record keeps marker spelling (`-`, `*`,
  or `+`) when a transform needs to reprint that node. Canonical formatting may
  choose a repository-wide marker only when doing so preserves list segmentation.
  For adjacent bullet lists whose only boundary is a marker change, such as
  `- foo\n+ bar`, CommonMark 0.31.2 §5.3 treats the marker change as starting a
  new list. Canonical formatting must preserve that structural boundary rather
  than merging both lists under one normalized marker.
- **Fenced code marker style.** Backtick fences and tilde fences can lower to the
  same code block when the info string and literal value are the same. Fence
  character and opening/closing fence width are surface metadata, so a local
  rewrite can preserve style while still choosing a safe wider fence if changed
  content requires it. Canonical formatting must also choose a fence character
  valid for the info string: CommonMark 0.31.2 forbids backticks in the info
  string after a backtick fence, so an info string containing backticks must use a
  tilde fence or another syntax-valid representation.
- **Tight vs spread lists.** `- a\n- b\n` and `- a\n\n- b\n` must not be
  collapsed blindly. List tightness/spread is a semantic field because it affects
  CommonMark rendering and mdast shape. Blank-line trivia may remain slice-only,
  but target adapters must receive the tight/spread value from IR.

Rules:

- Semantic canonicalization stops at the boundary where CommonMark rendering,
  mdast shape, or transform semantics would change. Tight versus spread lists are
  semantic; ATX versus setext heading form, unordered marker spelling, and fence
  character/count are surface.
- Surface metadata can still be boundary-bearing or syntax-validity-bearing. If
  normalizing a surface choice would merge or split CommonMark containers, as
  with adjacent bullet lists separated only by marker spelling, a canonical
  formatter must retain the structure by preserving a marker distinction or using
  an explicitly documented boundary-preserving strategy. If normalizing a fence
  character would make the info string or literal invalid for that fence form,
  the formatter must choose a syntax-valid character/count instead.
- Parser and incremental fast paths must share the same semantic boundary model
  for boundary-bearing surface metadata. Fast paths may be stricter than the
  full parser when a local replacement window cannot prove that a container's
  extent is unchanged; in that case they must decline reuse and let the normal
  incremental path preserve full-parse parity.
- Surface metadata is kept only for transform-relevant choices. Exact whitespace,
  blank-line runs, and untouched delimiter trivia remain in the source/CST and
  are recovered by slicing origins when unchanged.
- If a changed node lacks enough surface metadata for a local rewrite, the
  rewrite backend chooses a canonical or target-specific spelling for that node;
  it must not require generic CST token arrays on the IR node.

### Rewrite and formatter mode naming

Future rewrite/formatter APIs should make the mode visible in the function name
or in an explicit mode enum. Use names with these nouns:

- `preserve` / `PreserveRewrite` for source-slice preserving rewrites of
  unchanged nodes;
- `local_transform` / `LocalTransformRewrite` for rewrites that print changed IR
  subtrees and splice them into preserved source; and
- `canonical_format` / `CanonicalFormatter` for the backend that formats the
  whole document into normalized Markdown.

Avoid ambiguous names such as `canonicalize` for source-preserving rewrites or
`format` for local transforms. Semantic lowering may canonicalize meaning, but
canonical formatting is only one target backend over MarkdownIR.

---

## Extension scope

Baseline target: **CommonMark 0.31.2**. The first implementation slices may cover
less, but the core IR should not choose shapes that block CommonMark semantics.
Upgrading the baseline version is a contract change that must update examples,
fixtures, and adapter expectations together.

Raw HTML policy:

- CommonMark raw HTML block/inline support belongs in the baseline roadmap, but
  it must be represented explicitly as raw HTML block/inline IR nodes with
  origins and a literal/source-slice value, not as copied token trivia.
- MarkdownIR records the raw region and diagnostics/recovery facts only. It does
  not store a sanitizer decision, trust bit, or target-rendering policy.
- The mdast adapter may export mdast `html` nodes only when raw HTML export is
  enabled for that target. Otherwise it must use a documented target policy such
  as omission, escaping, or diagnostic-bearing rejection.
- The HTML renderer must expose an explicit mode: a CommonMark-conformance mode
  can pass raw HTML through for trusted fixtures; product-facing renderers should
  escape, drop, or sanitize unless the caller opts into unsafe passthrough.
  Unsafe passthrough must never be the unlabelled default.

Deferred extensions:

- **GFM** tables, task lists, strikethrough, and extension autolinks are deferred
  until the CommonMark baseline has a stable path. Add them in future milestones
  as explicit extension nodes or fields with adapter-specific behavior.
- **MDX** is out of core scope. JSX, ESM, and expression islands require a
  separate grammar/extension contract rather than weakening CommonMark IR nodes.
- **Frontmatter** is deferred. If added, represent it as a top-level extension
  preamble with origin and typed metadata, not as an unstructured token dump in
  the document body.

Extension nodes must preserve the same invariants as core nodes: explicit
origins, no arbitrary token cloning, adapter behavior defined for unsupported
extensions, and no silent weakening of CommonMark node contracts. An extension
may render/export, degrade to an explicit raw/recovered node with diagnostics, or
be rejected by a target adapter; it must not be smuggled through as an invalid
core node or force `Block` / `Inline` to carry extension-only payloads before the
editor projection contract changes.

---

## Recovered / Raw adapter contract

M4's adapter exit criterion is satisfied when every MarkdownIR target adapter has
explicit `Recovered` and `Raw` match arms. No adapter may silently drop these
variants or reinterpret them as if the malformed source had produced valid
semantic MarkdownIR.

| Adapter | Raw behavior | Recovered behavior | Rationale |
| --- | --- | --- | --- |
| Block (editor) | `Block::Error("expected block MarkdownIR, got raw: " + value)` | `Block::Error(message)` | Inline raw becomes `Inline::Text`; block-position raw is a defensive error. Recovered content is always an editor error. |
| Inline (editor) | `Inline::Text(value)` passthrough | `Inline::Error(message)` | Raw inline text renders as visible text. Recovered malformed delimiters become explicit error markers. |
| mdast JSON (export) | `mdastRaw` + origin + diagnostics | `mdastRecovered` + origin + diagnostics | Preserves full diagnostic/recovery fidelity for downstream tools. |
| Canonical format | value passthrough | `<!-- recovered MarkdownIR: msg -->` | Raw content transcludes literally. Recovery becomes an HTML comment. |
| Preserve/local (rewrite) | origin-slice passthrough | origin-slice / replacement_text passthrough | Preserve-mode reproduces exact source bytes via origin slicing. Local transform splices replacement text into recovered regions rather than silently losing edits. |

Policy rules:

1. **Safety**: Raw content must never be silently interpreted as semantic markup
   in any adapter. It must be visibly distinguished as an error node,
   diagnostic-bearing type, or explicit text passthrough with lossy semantics.
2. **Editor boundary**: Block-position raw is an error; inline raw is degraded to
   text. Recovered content is always an error.
3. **Export fidelity**: mdast preserves origin and diagnostics for toolchain
   consumption.
4. **Rewrite integrity**: preserve-mode must reproduce exact source bytes for
   raw/recovered regions; local transform must splice replacement text rather
   than silently dropping edits.
5. **Future adapters**: future targets, including HTML, must define their own
   `Recovered` / `Raw` policy: escape, drop, or sanitize by default, with opt-in
   passthrough only. The existing Raw HTML policy above governs CommonMark raw
   HTML. For recovery-node content, HTML adapters should use HTML comments or
   styled error spans, not unescaped markup injection.
6. **No guessing**: Target adapters must never infer malformed input from missing
   required semantic fields; they consume explicit `Recovered` / `Raw` nodes.

This contract is the adapter-level counterpart to the tree-shape invariant that
"Diagnostics and recovery are explicit nodes" and that target adapters must not
infer malformed input from absent required fields. It also complements the Raw
HTML policy in this section: raw CommonMark HTML has an explicit target policy,
and recovery-node content requires the same explicitness.

---

## Constructor and package-boundary policy

M0 introduces no public MarkdownIR types. This section is a policy gate for the
first implementation PRs, not permission to add placeholder APIs. MarkdownIR
public APIs should start deliberately: either explicitly experimental or
explicitly stable. Do not let generated interfaces accidentally decide the
contract.

Recommended policy for first public IR types:

- Default to opaque or privately-fielded records plus named constructors for any
  node that carries origins, diagnostics, surface metadata, or validated semantic
  fields.
- Use closed public enums for simple semantic alternatives that have no invalid
  payload combinations. Use broad public construction only for shapes that have
  no invalid states and are intentionally pattern-matched by downstream adapters.
- Avoid `pub(all)` for core IR records unless direct cross-package construction
  is the intended contract. MoonBit's ordinary public fields are not a validation
  boundary once a type is made broadly constructible.
- Keep package-private unchecked constructors, if any, visibly internal and out
  of generated public interfaces. They are allowed only to factor trusted lowering
  code after validation has already happened.
- Public constructors or builders must validate heading depth, list kind/start,
  list spread/tightness, code-block value/info/surface consistency, link/image
  destinations and reference shape, origins, and recovered/raw regions. Invalid
  construction returns an explicit error or diagnostic-bearing value; it must not
  silently clamp, drop, or invent semantic fields.
- Validation helpers should be owned by the IR package and reused by both
  hand-written constructors and CST lowering. Target adapters should consume a
  valid IR value, not repeat invariant checks to defend against malformed core
  nodes.
- Canopy/editor code should depend on stable adapters such as IR-to-`Block`,
  mdast export, rewrite, or render entry points. It should not construct or
  mutate internal IR nodes directly unless a future API intentionally grants that
  capability.
- Every public IR API change must review generated `.mbti` output for unintended
  constructors, mutable fields, widened trait bounds, unchecked helpers, or
  target-only details that leaked into core IR.

Implementation PRs that introduce constructors should add tests for invalid
heading/list/code/link construction paths and tests proving that different
surface spellings can share semantic shape while preserving distinct surface
metadata.

Generated-interface review gate:

- The first public IR PR must include `moon info` output review for
  `examples/markdown/src/pkg.generated.mbti` and for any new IR or Canopy package
  interfaces it changes.
- Review constructor and field visibility, `pub(all)` exposure, mutable fields,
  unchecked helpers, widened trait bounds, target-only payloads, and whether the
  compatibility floor above still holds.
- If a PR intentionally exposes broad construction or pattern matching, the PR
  must explain which invariants are impossible to violate through that surface.
- If a PR is docs-only or intentionally has no generated-interface diff, state
  that explicitly; do not run `moon info` just to manufacture churn.

### Implementation review checklist

When this contract turns into code, reviewers should first verify that the PR:

- preserves existing parser signatures and compatibility tests, including
  LexError-raising `parse_markdown` and `parse_cst` behavior;
- lowers from `SyntaxNode`/CST plus source origins into typed IR, without generic
  token or trivia arrays on semantic nodes;
- models raw HTML, unsupported extensions, and recovery explicitly, with target
  adapter behavior stated;
- keeps Canopy on `Block` / `Inline` unless the PR is the explicit compatibility
  migration; and
- includes either deliberate `.mbti` diffs from `moon info` or an explicit note
  that no generated-interface change is expected.

---

## Phase ordering

Validation order is fixed: IR invariants first, target fixture parity second,
incremental parity third, and fast paths last.

| Phase | Scope | Exit signal |
|---|---|---|
| M0 — Contracts and roadmap | #323, #331, #337, #340, #335, #336. Define responsibilities, invariants, constructor/API policy, canonicalization vocabulary, extension scope, migration plan, and package boundaries. | Contract docs are present and reviewed; `Block`/`Inline` compatibility is explicit; mdast is documented as an export target; no implementation begins without the field-promotion rubric, invariants, CST boundary, constructor policy, and generated-interface review gate. |
| M1 — Minimal vertical slice | #338, #324, #339. Current parser subset through `SyntaxNode -> MarkdownIR -> Block/Inline`, mdast export, rewrite smoke tests, and performance policy. | Existing parser behavior and `Block`/`Inline` tests still pass for headings, paragraphs, unordered lists, fenced code, and parsed inline containers; mdast snapshots exist for the slice; preserve/local/canonical modes are distinguishable; new public IR APIs are deliberately experimental or stable; generated interfaces are reviewed. |
| M2 — Editor projection compatibility | #332, #341. Derive the editor model from MarkdownIR and define projection identity policy. | Canopy projection memos can continue consuming `@markdown.Block`; source-map roles have a documented source of truth; surface-only edits do not churn editor identity unless the view requires it. |
| M3 — mdast export parity | #325. Fixture parity harness over MarkdownIR. | Checked-in mdast fixtures run under `moon test`; generator workflow is optional; pass/xfail baseline is explicit. |
| M4 — Source origins and rewrites | #328, #333, #334. Centralized origins, unist positions, rewrite modes, diagnostics/recovery/raw-node contract. | Origins and position conversions are documented and tested; unchanged source can be reproduced by slicing; adapters handle `Recovered`/`Raw` nodes explicitly; remaining feature-specific raw/recovery expansion is tracked against later CommonMark milestones. |
| M5 — CommonMark block model | #326, #327. CommonMark HTML harness and block/container semantics. | HTML fixture baseline exists; list/container flow content is represented in IR; block-feature additions include full-vs-incremental parity before reuse assertions. |
| M6 — CommonMark inline model | #329. Inline delimiter, link/reference, code-span, escape, entity, break, and image semantics. | Inline mdast and HTML fixture coverage improves feature-by-feature; document-level reference resolution has an explicit IR contract. |
| M7 — Incremental hardening | #330. Preserve parser/diagnostic/IR parity as features expand. | Each new Markdown feature has full-vs-incremental CST, diagnostic, and target parity tests before any block-reparse widening; richer block-reparse context remains evidence-driven. |

## M0 exit criteria

M0 is done when:

- the responsibility table above is the reviewed target contract;
- the anti-CST-cloning rule and field-promotion rubric are referenced by IR
  implementation issues;
- origin, tree-shape, semantic-node, and surface-metadata invariants are
  documented;
- the CST lowering boundary states what may be read from `SyntaxNode` and what
  must not be copied into IR;
- constructor visibility, validation-helper ownership, implementation-test
  obligations, and the policy-level generated-interface review gate are
  documented;
- the extension scope states CommonMark baseline, raw HTML policy, and deferred
  GFM/MDX/frontmatter handling;
- the migration plan preserves current parser and editor APIs until an explicit
  compatibility PR changes them; and
- no MarkdownIR implementation has to guess whether it is building a semantic
  layer, an editor model, an mdast clone, or a CST clone.

## M1 exit criteria

M1 is done when the current parser subset proves the contract end to end:

- `SyntaxNode -> MarkdownIR` lowering exists for headings, paragraphs,
  unordered lists, list items, fenced code blocks, text, bold, italic, inline
  code, and links;
- `MarkdownIR -> Block/Inline` preserves current editor-facing behavior;
- `MarkdownIR -> mdast` snapshots exist for the slice;
- preserve-mode, local-transform, and canonical formatter smoke tests are
  visibly different where surface metadata matters;
- eager/lazy and memoization policy is stated with an initial benchmark
  (see [ADR 2026-06-16](../decisions/2026-06-16-markdown-ir-performance-policy.md));
  the benchmark compares `SyntaxNode -> Block` with
  `SyntaxNode -> MarkdownIR -> Block` on a mixed document and concludes that
  MarkdownIR is built lazily on demand without `CstFold` because its absolute
  source origins are position-dependent; and
- `.mbti` diffs show the intended public construction surface only.
