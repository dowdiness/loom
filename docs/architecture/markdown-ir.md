# MarkdownIR: Architecture and Target Contract

**Status:** M0 target contract for [#323](https://github.com/dowdiness/loom/issues/323)
**Related:** [#331](https://github.com/dowdiness/loom/issues/331), [#337](https://github.com/dowdiness/loom/issues/337), [#340](https://github.com/dowdiness/loom/issues/340), [#335](https://github.com/dowdiness/loom/issues/335), [#336](https://github.com/dowdiness/loom/issues/336)

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
4. **Malformed or unsupported input:** becomes an explicit `Raw`/`Recovered`
   style IR node with origin and diagnostics. It must not become a token pile on
   otherwise semantic nodes.
5. **Target-only data:** stays in the adapter for mdast, HTML, or the editor if
   it is not core semantic or transform-relevant data.

Reject designs with generic `tokens`, `children_tokens`, all-trivia arrays, or
APIs that require target adapters to inspect raw token lists to understand a
semantic node.

Origins are references back to source/CST, not a second copy of the document.
Internal origins use Loom's UTF-16 code-unit offsets; line/column and unist
position objects are export-boundary conversions.

---

## Canonicalization and formatting vocabulary

Use these terms consistently:

- **Semantic canonicalization:** different concrete syntaxes lower to the same
  semantic IR shape when they mean the same thing. An ATX heading and a setext
  heading can be the same semantic heading; `-` and `*` can be the same
  unordered list kind.
- **Surface preservation:** selected syntax choices remain attached as metadata
  when transforms need them. Heading form, list marker spelling, and code-fence
  character/count are surface metadata; arbitrary whitespace is not promoted
  unless a transform needs it.
- **Preserve-mode rewrite:** unchanged IR nodes reuse original source slices via
  origins. MarkdownIR alone is not expected to print byte-for-byte source.
- **Local transform rewrite:** changed nodes render from IR, using semantic fields
  plus relevant surface metadata, while unchanged surrounding ranges are sliced
  from the original source.
- **Canonical formatter mode:** a target backend that intentionally ignores
  existing surface style and emits normalized Markdown. Canonical formatting is
  not the definition of MarkdownIR.

List tightness/spread is semantic because it affects rendered structure. Fence
marker spelling is surface metadata because the code block semantics can be the
same while the local rewrite may want to preserve the author's fence style.

---

## Extension scope

Baseline target: **CommonMark 0.31.x**. The first implementation slices may cover
less, but the core IR should not choose shapes that block CommonMark semantics.

Raw HTML policy:

- CommonMark raw HTML block/inline support belongs in the baseline roadmap, but
  it must be represented explicitly as raw HTML IR nodes with origins and a
  literal/source-slice value, not as copied token trivia.
- The mdast adapter may export mdast `html` nodes only when raw HTML export is
  enabled for that target.
- The HTML renderer must expose an explicit mode: a CommonMark-conformance mode
  can pass raw HTML through for trusted fixtures; product-facing renderers should
  escape, drop, or sanitize unless the caller opts into unsafe passthrough.

Deferred extensions:

- **GFM** tables, task lists, strikethrough, and extension autolinks are deferred
  until the CommonMark baseline has a stable path. Add them as explicit extension
  nodes or fields with adapter-specific behavior.
- **MDX** is out of core scope. JSX, ESM, and expression islands require a
  separate grammar/extension contract rather than weakening CommonMark IR nodes.
- **Frontmatter** is deferred. If added, represent it as a top-level extension
  preamble with origin and typed metadata, not as an unstructured token dump in
  the document body.

Extension nodes must preserve the same invariants as core nodes: explicit
origins, no arbitrary token cloning, adapter behavior defined for unsupported
extensions, and no silent weakening of CommonMark node contracts.

---

## Constructor and package-boundary policy

MarkdownIR public APIs should start deliberately: either explicitly experimental
or explicitly stable. Do not let generated interfaces accidentally decide the
contract.

- Prefer named constructors or smart builders for nodes with invariants: heading
  depth, list kind/start/spread, code-block info/value/surface metadata, link
  destinations, origins, and recovered/raw regions.
- Use broad public construction only for shapes that have no invalid states and
  are intended for direct pattern matching by downstream adapters.
- Keep validation close to construction. Lowering code may use internal helpers,
  but anything crossing the package boundary must already satisfy the documented
  invariants or return diagnostics.
- Canopy/editor code should depend on stable adapters such as IR-to-`Block`,
  mdast export, rewrite, or render entry points. It should not construct or
  mutate internal IR nodes directly unless a future API intentionally grants that
  capability.
- Every public IR API change must review generated `.mbti` output for unintended
  constructors, mutable fields, widened trait bounds, or target-only details that
  leaked into core IR.

---

## Phase ordering

Validation order is fixed: IR invariants first, target fixture parity second,
incremental parity third, and fast paths last.

| Phase | Scope | Exit signal |
|---|---|---|
| M0 — Contracts and roadmap | #323, #331, #337, #340, #335, #336. Define responsibilities, invariants, constructor/API policy, canonicalization vocabulary, extension scope, migration plan, and package boundaries. | Contract docs are present and reviewed; `Block`/`Inline` compatibility is explicit; mdast is documented as an export target; no implementation begins without the field-promotion rubric and API boundary policy. |
| M1 — Minimal vertical slice | #338, #324, #339. Headings and paragraphs through `SyntaxNode -> MarkdownIR -> Block/Inline`, mdast export, rewrite smoke tests, and performance policy. | Existing heading/paragraph parser behavior and `Block`/`Inline` tests still pass; mdast snapshots exist for the slice; preserve/local/canonical modes are distinguishable; new public IR APIs are deliberately experimental or stable; generated interfaces are reviewed. |
| M2 — Editor projection compatibility | #332, #341. Derive the editor model from MarkdownIR and define projection identity policy. | Canopy projection memos can continue consuming `@markdown.Block`; source-map roles have a documented source of truth; surface-only edits do not churn editor identity unless the view requires it. |
| M3 — mdast export parity | #325. Fixture parity harness over MarkdownIR. | Checked-in mdast fixtures run under `moon test`; generator workflow is optional; pass/xfail baseline is explicit. |
| M4 — Source origins and rewrites | #328, #333, #334. Centralized origins, unist positions, rewrite modes, diagnostics/recovery/raw-node contract. | Origins and position conversions are documented and tested; unchanged source can be reproduced by slicing; adapters handle recovery nodes explicitly. |
| M5 — CommonMark block model | #326, #327. CommonMark HTML harness and block/container semantics. | HTML fixture baseline exists; list/container flow content is represented in IR; block-feature additions include full-vs-incremental parity before reuse assertions. |
| M6 — CommonMark inline model | #329. Inline delimiter, link/reference, code-span, escape, entity, break, and image semantics. | Inline mdast and HTML fixture coverage improves feature-by-feature; document-level reference resolution has an explicit IR contract. |
| M7 — Incremental hardening | #330. Preserve parser/diagnostic/IR parity as features expand. | Each new Markdown feature has full-vs-incremental CST, diagnostic, and target parity tests before any block-reparse widening; richer block-reparse context remains evidence-driven. |

## M0 exit criteria

M0 is done when:

- the responsibility table above is the reviewed target contract;
- the anti-CST-cloning rule and field-promotion rubric are referenced by IR
  implementation issues;
- constructor visibility and generated-interface review policy are documented;
- the extension scope states CommonMark baseline, raw HTML policy, and deferred
  GFM/MDX/frontmatter handling;
- the migration plan preserves current parser and editor APIs until an explicit
  compatibility PR changes them; and
- no MarkdownIR implementation has to guess whether it is building a semantic
  layer, an editor model, an mdast clone, or a CST clone.

## M1 exit criteria

M1 is done when a heading/paragraph slice proves the contract end to end:

- `SyntaxNode -> MarkdownIR` lowering exists for headings and paragraphs;
- `MarkdownIR -> Block/Inline` preserves current editor-facing behavior;
- `MarkdownIR -> mdast` snapshots exist for the slice;
- preserve-mode, local-transform, and canonical formatter smoke tests are
  visibly different where surface metadata matters;
- eager/lazy and memoization policy is stated with an initial benchmark; and
- `.mbti` diffs show the intended public construction surface only.
