# `dowdiness/markdown`

Markdown parser example for [`dowdiness/loom`](../../loom/).

Demonstrates **mode-aware lexing** — `@core.ModeLexer[Token, Mode]` —
the way to handle languages whose token grammar depends on the current
context (line start vs inline vs inside a fenced code block).

## Public API overview

This section highlights the main entry points.

```mbt nocheck
// ── Grammar ───────────────────────────────────────────────────────────────────

pub let markdown_grammar    : @loom.Grammar[Token, SyntaxKind, Block]
pub let markdown_spec       : @core.LanguageSpec[Token, SyntaxKind]
pub let markdown_mode_lexer : @core.ModeLexer[Token, MarkdownLexMode]

// ── High-level parsing ────────────────────────────────────────────────────────

pub fn parse(@core.SourceId, String) -> Block                              // lex errors fold into Block::Error
pub fn parse_markdown(@core.SourceId, String) -> (Block, @core.DiagnosticSet) // returns diagnostics
  raise @core.LexError
pub fn parse_cst(@core.SourceId, String) -> (@seam.CstNode, @core.DiagnosticSet)
  raise @core.LexError
// `parse_document` is the source-bound snapshot entry point.
pub fn parse_document(@core.SourceId, String) -> MarkdownDocument
  raise @core.LexError

// ── CST → AST ─────────────────────────────────────────────────────────────────

pub fn markdown_fold_node(@seam.SyntaxNode, (@seam.SyntaxNode) -> Block) -> Block

// ── Parser-backed editor role spans ───────────────────────────────────────────

pub fn project_markdown_roles(@seam.SyntaxNode) -> Array[MarkdownRoleSpan]
pub fn export_markdown_role_spans(Array[MarkdownRoleSpan]) -> Json
pub fn attach_markdown_role_spans(@loom.SyntaxParser) -> MarkdownRoleSpansAttachment

// ── Parser-backed editor Block projection ────────────────────────────────────

pub fn attach_markdown_projection(@loom.SyntaxParser) -> MarkdownProjectionAttachment

// ── Experimental MarkdownIR M1 slice ──────────────────────────────────────────

pub fn experimental_markdown_ir_from_syntax(
  @core.SourceId, @seam.SyntaxNode
) -> MarkdownIR
pub fn experimental_markdown_ir_from_syntax_with_diagnostics(
  @core.SourceId, @seam.SyntaxNode, @core.DiagnosticSet
) -> MarkdownIR
pub fn experimental_markdown_ir_to_block(MarkdownIR) -> Block
pub fn experimental_markdown_ir_to_mdast_json(MarkdownIR) -> Json
pub fn experimental_markdown_ir_to_mdast_json_with_positions(MarkdownIR, String) -> Json
pub fn experimental_markdown_ir_preserve_rewrite(MarkdownIR, String) -> String
pub fn experimental_markdown_ir_local_transform_rewrite(
  MarkdownIR, String, target_origin~ : MarkdownIROrigin, replacement_text~ : String
) -> String
pub fn experimental_markdown_ir_canonical_format(
  @core.SourceId, MarkdownIR
) -> String
pub fn experimental_markdown_ir_canonical_format_checked(
  @core.SourceId, MarkdownIR
)
  -> Result[String, MarkdownIRCanonicalFormatFailure]
pub(all) enum RawHtmlPolicy {
  Escape
  Omit
  Reject
  Passthrough
}
pub(all) enum RawHtmlSurface {
  RawHtmlBlock
  RawHtmlInline
}
pub(all) enum MarkdownIRHtmlRenderError {
  RawHtmlRejected(RawHtmlSurface, MarkdownIROrigin)
}
pub fn experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
  MarkdownIR, RawHtmlPolicy
) -> Result[String, MarkdownIRHtmlRenderError]
pub fn experimental_markdown_ir_to_commonmark_html(MarkdownIR) -> String

// ── Source-bound semantic document ───────────────────────────────────────────

pub struct MarkdownDocument
pub fn MarkdownDocument::source_id(MarkdownDocument) -> @core.SourceId
pub fn MarkdownDocument::source(MarkdownDocument) -> String
pub fn MarkdownDocument::diagnostics(MarkdownDocument) -> @core.DiagnosticSet
pub fn MarkdownDocument::semantic_read(MarkdownDocument) -> MarkdownSemanticRead
pub struct MarkdownSemanticRead
pub fn MarkdownSemanticRead::ir(MarkdownSemanticRead) -> MarkdownIR
pub fn MarkdownSemanticRead::root(MarkdownSemanticRead) -> MarkdownSemanticReadNode
pub struct MarkdownSemanticReadNode
pub fn MarkdownSemanticReadNode::children(MarkdownSemanticReadNode)
  -> Array[MarkdownSemanticReadNode]
pub fn MarkdownSemanticReadNode::view(MarkdownSemanticReadNode) -> MarkdownIRView
pub fn MarkdownSemanticReadNode::origin(MarkdownSemanticReadNode) -> MarkdownIROrigin
pub fn MarkdownSemanticReadNode::selection(
  MarkdownSemanticReadNode, kind~ : MarkdownSemanticSelectionKind
) -> MarkdownSemanticSelection?
pub struct MarkdownSemanticSelection
pub(all) enum MarkdownSemanticSelectionKind {
  WholeNode
  Content
  Destination
  Title
  AutolinkDisplay
}
pub fn markdown_semantic_read_to_block(MarkdownSemanticRead) -> Block
pub fn markdown_semantic_read_to_mdast_json_with_positions(
  MarkdownSemanticRead
) -> Json
pub fn markdown_semantic_read_preserve_rewrite(MarkdownSemanticRead) -> String
pub fn markdown_semantic_read_local_transform_rewrite(
  MarkdownSemanticSelection, replacement_text~ : String
) -> String
pub fn MarkdownSemanticAttachment::source_document(
  MarkdownSemanticAttachment
) -> MarkdownDocument

// ── Lexing ────────────────────────────────────────────────────────────────────

pub fn tokenize(String) -> Array[@core.TokenInfo[Token]] raise @core.LexError
pub fn markdown_lex_step(String, Int, MarkdownLexMode)
  -> (@core.LexStep[Token], MarkdownLexMode)
```

Full signatures: [`pkg.generated.mbti`](pkg.generated.mbti).

Note that `parse` is **not** `raise` — lexing failures fold into
`Block::Error`, while parser recovery may preserve malformed inline source as
text or error-shaped IR. If you need diagnostics, use `parse_markdown` instead.
Pass the same stable `SourceId` through parsing, diagnostic-aware lowering, and
canonical-format verification for one source snapshot. A producer name is not
a source identity, and `tokenize(String)` remains the source-agnostic raw lexer
entry point.

### Emphasis token and CST compatibility

CommonMark delimiter runs are resolved by the native inline parser. The public
`Star` / `StarStar` token variants and their existing syntax-kind raw IDs remain
available, but inline-text lexing now emits one `Star` fact for each unescaped
`*` and an append-only `Underscore` fact for each unescaped `_`; it no longer
emits `StarStar` for inline `**`. `UnderscoreToken` (raw kind 39) and
`EmphasisDelimiterToken` (raw kind 40) are append-only syntax kinds.

This intentionally changes the observable `tokenize` and `parse_cst` shape.
Characters consumed as bold or italic boundaries are
`EmphasisDelimiterToken` leaves, while unmatched, escaped, or unused run
portions are ordinary `TextToken` leaves. Existing variants and raw IDs were
not removed or reused. Consumers that inspect Markdown CST should classify
editable delimiter roles by the boundary token kind, not by marker spelling or
by the enclosing `BoldNode` / `ItalicNode` alone.

### Typed angle-node compatibility (#891)

The CST registry now has three append-only node kinds: `UriAutolinkNode`
(raw kind 42), `EmailAutolinkNode` (43), and `InlineHtmlNode` (44). They are a
consumer compatibility surface for source-backed typed CST fixtures. Their
children retain the original spelling and origins, and MarkdownIR lowering
projects them to the existing `Autolink` and `InlineHtml` variants.

Production ownership is now singular. Inline lexing emits source-faithful
one-character `Text` boundaries for unescaped `<` and every `>`, preserves
backtick runs, and keeps escaped `<` inside maximal literal text so it cannot
open a candidate. The container-local
inline plan alone classifies URI autolinks, email autolinks, and inline HTML,
then emits the typed nodes after resolving code, link, and destination
precedence. Block-HTML opening remains lexer-owned because it selects a lexical
mode. Generic `TextToken` lowering never reclassifies angle spelling.

The source-wide lexer angle index and parser branches for collapsed `<...>`
tokens have been removed. The standalone compatibility fixtures still use the
exact metadata domain produced by `LanguageSpec::new(ErrorToken, ErrorNode,
...)`; no token, raw kind, MarkdownIR variant, parser entry point, generic Loom
API, or public Markdown role changed. See the
[compatibility inventory](../../docs/api/markdown-typed-angle-cst-compatibility.md),
the [typed CST compatibility ADR](../../docs/decisions/2026-08-06-markdown-typed-angle-cst-compatibility.md),
and the [final ownership ADR](../../docs/decisions/2026-08-08-markdown-inline-angle-parser-ownership.md).

## Experimental MarkdownIR

The M1 MarkdownIR API is explicitly experimental. It covers the current parser
subset: document, heading, paragraph, unordered list, list item, fenced code,
text, bold, italic, inline code, and link nodes with UTF-16 source origins.
Unsupported Markdown constructs lower to explicit `Unsupported` IR nodes rather
than token/trivia arrays.

External adapters should match `MarkdownIR::view()` to inspect semantic node
kinds and their meaning-bearing fields exhaustively. Use `children()`,
`origin()`, `content_origin()`, and `diagnostics()` for the common tree and
source-attachment facts; returned child and diagnostic arrays are defensive
copies. The older kind tag, optional field accessors, and opaque-node predicates
remain compatible during the experimental migration, but they are not the
preferred surface for a new exhaustive adapter.

Use `experimental_markdown_ir_from_syntax` after `parse_cst` when you need the
IR, then adapt with `experimental_markdown_ir_to_block`, export with
`experimental_markdown_ir_to_mdast_json` or
`experimental_markdown_ir_to_mdast_json_with_positions`, or smoke-test rewriting
with `experimental_markdown_ir_preserve_rewrite`,
`experimental_markdown_ir_local_transform_rewrite`,
`experimental_markdown_ir_canonical_format`, its checked counterpart
`experimental_markdown_ir_canonical_format_checked`, or render CommonMark-style
HTML with `experimental_markdown_ir_to_commonmark_html`. The HTML renderer uses
`RawHtmlPolicy::Escape` as its safe product default. Call
`experimental_markdown_ir_to_commonmark_html_with_raw_html_policy` to make an
intentional `Escape`, `Omit`, `Reject`, or `Passthrough` decision at a trust
boundary. `Reject` returns `MarkdownIRHtmlRenderError::RawHtmlRejected` with the
HTML surface and source origin. Malformed recovery `Raw` is not valid HTML and
remains escaped under every policy. mdast export is independent of rendering
policy and continues to preserve valid HTML as an `html` node. The
position-aware mdast export must receive the exact source string that produced
the IR. The established parser surfaces (`parse`, `parse_markdown`, `parse_cst`,
`markdown_grammar`, and `markdown_fold_node`) remain the one-shot and
`Parser[Block]` compatibility path. Long-lived editor integrations can attach
the keyed path with `attach_markdown_projection` while continuing to consume
the same `Block` / `Inline` model. Source-aware integrations over an existing
`Parser[Block]` can instead construct `MarkdownSemanticAttachment(parser)` and
consume the complete owning MarkdownIR document through `document()`.

### Source-bound semantic document

`parse_document(source_id, source)` owns one complete source, syntax snapshot,
and parser `DiagnosticSet`. Construction is lazy with respect to MarkdownIR;
`semantic_read()` is the explicit eager step that creates one detached
`MarkdownSemanticRead` and lowers MarkdownIR exactly once for that handle.
`MarkdownSemanticRead::root()` exposes read-bound nodes. Their observational
`view()`/`origin()` and `children()` methods support navigation, while
`selection(kind~)` creates an opaque target that remains tied to the same read.
Missing content, destination, title, or autolink-display targets return `None`.

The three source-aware adapters consume the read:
`markdown_semantic_read_to_block`,
`markdown_semantic_read_to_mdast_json_with_positions`, and
`markdown_semantic_read_preserve_rewrite`. The local-transform adapter consumes
only a `MarkdownSemanticSelection` plus replacement text. IR-only targets such
as HTML, position-free mdast, and canonical formatting continue to consume
`read.ir()` through their existing compatibility functions.


### Keyed editor projection attachment

`MarkdownProjectionAttachment` owns the retained keyed MarkdownIR computation,
adapts it through `experimental_markdown_ir_to_block`, and returns a detached
current `Block` from `projection()`. The parser remains caller-owned. After an
editor has atomically committed the returned projection, call `collect()` at
that safe point; it reads the terminal projection and delegates GC plus all
keyed-map retirement to the attachment's Incr scope. Call `dispose()` when the
editor closes. Consumers never call runtime GC or individual map sweeps.

Direct `experimental_markdown_ir_from_syntax*` calls stay one-shot and allocate
no keyed caches. MarkdownIR origins remain semantic attachment; exact editable
roles still come from CST-backed role spans and the editor's current source
map. The attachment deliberately exposes neither representation as the other.

### Source-aware semantic attachment

`MarkdownSemanticAttachment` joins an existing caller-owned `Parser[Block]`
runtime. Its custom constructor creates no second parser. `document()` remains
the existing terminal `MarkdownIR` read and performs its established
scope-owned collection before returning. `source_document()` is the
separately named owning `MarkdownDocument` read: it captures the parser
snapshot before collection, and the returned document remains valid after later
parser edits, collection, and attachment disposal.

The attachment does not provide revisions, deltas, acknowledgements, watches,
scopes, cache keys, or collection operations. Reading after disposal is a
contract violation. The legacy `MarkdownProjectionAttachment` remains the
smaller `Block` path and retains its caller-selected post-commit `collect()`
boundary.

### Checked canonical formatting

Use `experimental_markdown_ir_canonical_format_checked` when the caller needs a
semantic guarantee rather than compatibility output. It accepts only a
`MarkdownIR::Document` containing semantic nodes. Before returning `Ok`, it
reparses each finite, deterministically ordered candidate with `parse_cst`,
lowers it with diagnostics, and compares the whole document while ignoring
origins, surface spellings, and adjacent `Text` segmentation. Meaning-bearing
fields such as heading depth, list start/spread, emphasis structure, code
payload, and link destination remain part of the comparison.

The checked API returns `ExpectedDocument`, `OpaqueNode`, `Unrepresentable`, or
`SearchLimitExceeded` instead of emitting an unverified string. `Raw`,
`Recovered`, and `Unsupported` are rejected before search; when several occur,
the first preorder node is reported. Candidate spelling is stable: lower UTF-16
growth first, then literal/backslash/numeric-reference text encoding, `*` before
`_` emphasis markers, and finally lexical order. Search is bounded per inline
container and by a document limit scaled by container count.

`experimental_markdown_ir_canonical_format` remains the compatibility API. A
semantic document delegates to the checked implementation and fails fast if it
cannot be proven. Non-document roots and documents containing opaque nodes keep
their previous unchecked output: `Raw(value, _)` emits `value`, parse-error
`Recovered` emits `<!-- recovered MarkdownIR: parse error -->`, any other
`Recovered(message, _)` emits `message`, and `Unsupported(message)` emits
`<!-- unsupported MarkdownIR: message -->`.

### Projection identity policy

The private MarkdownIR identity adapter extracts content-attached, typed
semantic leaves and previews the full sequence through Loom's
`ProjectionIdentityTracker`. It commits only after a successful MarkdownIR
projection. `Raw`, `Recovered`, and `Unsupported` nodes receive no durable ID;
failed input retains the last successful baseline for recovery.

Surface-only rewrites retain IDs when their semantic payload is unchanged:
ATX/setext headings, unordered-marker spelling, and code-fence character or
width. Heading depth, list semantics, code language, payload text, and link
destination changes receive fresh IDs. Link-label formatting may retain an ID
when its lowered child fingerprint is unchanged; changed label content does not.
Local continuity requires a unique match on typed key, matched parent context,
and semantic payload. Duplicate siblings and descendants without a matched
parent receive fresh IDs rather than retaining a generic preview ID.

`MarkdownNodeId` is intentionally private. `Block` / `Inline`, `ProjNode`, and
`SourceMap` remain view-local compatibility surfaces. The Canopy-owned
`ProjNode` attachment path is not implemented in this package; a later
compatibility PR must rebuild that mapping from the current projection rather
than persist a path or `ProjNode` ID in the identity baseline.

### Unicode punctuation and symbol data

`unicode_punctuation_symbol.mbt` is generated from the checked-in Unicode
16.0.0 `DerivedGeneralCategory` data. The generator verifies the pinned input
SHA-256 before selecting the CommonMark `P*` and `S*` general categories and
merging adjacent ranges. Normal tests consume only the generated MoonBit table
and remain hermetic. The Unicode copyright and permission notice is checked in
as `tools/UNICODE-LICENSE.txt` alongside the source data.

To regenerate the table from `examples/markdown`:

```bash
python3 tools/gen_unicode_punctuation_symbol.py
NEW_MOON_MOD=0 moon fmt
git diff --exit-code -- unicode_punctuation_symbol.mbt
```

### mdast fixture parity

`mdast_fixture_parity_test.mbt` compares MarkdownIR mdast export against checked-in
reference fixtures embedded in `mdast_fixture_data_test.mbt`. The harness parses
Markdown to MarkdownIR and calls `experimental_markdown_ir_to_mdast_json`; it does
not route through the editor-facing `Block` model. Fixture status metadata
supports `Pass`, `Xfail(reason)`, and `Skip(reason)`, with the current baseline
summarized in the generated data file header.

Normal MoonBit CI is hermetic: `moon test` consumes the checked-in fixtures and
does not require Node, npm, or network access. To deliberately refresh the
reference mdast JSON from the JavaScript ecosystem, run the optional non-CI
generator from `examples/markdown`:

```bash
npm exec --package=mdast-util-from-markdown -- node tools/update_mdast_fixtures.mjs
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon test
```

The generator canonicalizes mdast by dropping `position`, `null` defaults, and
`spread: false` fields so the fixtures target the current MarkdownIR mdast
surface rather than unist position export or later CommonMark/container work.

### CommonMark HTML fixture parity

`commonmark_html_fixture_test.mbt` compares MarkdownIR HTML rendering against
checked-in official CommonMark 0.31.2 examples. The harness parses Markdown to
MarkdownIR and explicitly selects `RawHtmlPolicy::Passthrough`, as required by
the CommonMark rendering contract; it does not route through mdast. Product
callers that use the convenience renderer retain the safe `Escape` default.
mdast fixture parity proves adapter tree shape, while CommonMark HTML parity
proves rendered behavior and escaping.

For numbered CommonMark fixtures, the pinned
`tools/commonmark-0.31.2-spec.json` file is the sole normative oracle for source
and expected HTML. Its SHA-256 is
`d431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20`.
For emphasis examples 350 through 481,
`tools/commonmark_html_fixture_overrides.json` may only classify a non-pass case
and give its reason; it never replaces or duplicates the official expected
HTML. `tools/update_commonmark_emphasis_fixtures.mjs` combines those two pinned
inputs into `commonmark_emphasis_html_fixture_data_test.mbt`.

The emphasis baseline is 132 pass, 0 xfail, and 0 skip. Inline HTML and URI
autolinks keep delimiter-looking text opaque, so examples 475–477 and 480–481
now match the official HTML. Pass fixtures must continue matching that oracle,
while any future xfail that starts matching must be promoted to pass. Fixture
metadata records the CommonMark section, example number, source, expected HTML,
and `CommonMarkHtmlPass` / `CommonMarkHtmlXfail(reason)` /
`CommonMarkHtmlSkip(reason)` status.

To regenerate the emphasis fixtures from `examples/markdown`:

```bash
node tools/update_commonmark_emphasis_fixtures.mjs
NEW_MOON_MOD=0 moon fmt commonmark_emphasis_html_fixture_data_test.mbt
NEW_MOON_MOD=0 moon test commonmark_html_fixture_test.mbt
```

Node is needed only for deliberate regeneration. Normal MoonBit checks consume
the checked-in fixture data and require no Node, npm, or network access.

The repository-owned audit is a comparison signal, not another oracle. To
inspect the full CommonMark 0.31.2 corpus without turning it into a CI gate, run
this optional command from `examples/markdown`:

```bash
NEW_MOON_MOD=0 moon run src/tools/commonmark_html_audit --target native
```

The command verifies the version, SHA-256, and 652-example total of the pinned
`tools/commonmark-0.31.2-spec.json` corpus before auditing it. The audit selects
`RawHtmlPolicy::Passthrough` explicitly and records any structured policy error
as `adapter-policy-rejection`. It prints one
machine-readable category per example and section totals for parser diagnostics,
`Unsupported`, malformed `Raw`, `Recovered`, adapter-policy rejection, and HTML
mismatch. `render-match` is separate evidence: it preserves the original 437
HTML matches, while only the 405 examples with matching HTML and no diagnostic,
opaque, or recovery assistance count as `pass`. Use `-- --spec path/to/spec.json`
only to point at an identical copy of the pinned corpus.
Third-party parsers are optional comparison signals only: they cannot override
the pinned official source or HTML, and any comparison tool added to this
workflow must use an exact version pin.

## Grammar

`markdown_grammar` is the single integration surface. Pass it to
[`@loom`](../../loom/) factories:

```mbt check
///|
test "grammar example: imperative parser returns a Block" {
  let source_id = @core.SourceId("markdown-readme-imperative")
  let imp = @loom.new_imperative_parser(
    source_id, "# Hello\n", markdown_grammar,
  )
  let doc = imp.parse().ast
  // The top-level Block is always a Document containing the parsed blocks.
  match doc {
    Document(_) => ()
    _ => abort("expected Document at top level")
  }
}

///|
test "grammar example: reactive parser + set_source" {
  let source_id = @core.SourceId("markdown-readme-reactive")
  let parser = @loom.new_parser(source_id, "# Hello\n", markdown_grammar)
  parser.set_source("## World\n")
  let doc : Block = parser.ast().read_or_abort()
  match doc {
    Document(_) => ()
    _ => abort("expected Document at top level")
  }
}
```

## Parser-backed editor role spans

`project_markdown_roles` is a pure `SyntaxNode` projector over the current
recovered CST. Its typed spans expose `role()`, `start()`, and `end()` readers
and use the parser's source-backed UTF-16 token ranges; synthetic zero-width
recovery tokens are omitted. For a stateful editor session,
`attach_markdown_role_spans` shares the parser runtime and keeps the projection
reachable through a persistent `Scope`/`Watch` attachment. `spans()` returns a
defensive copy; callers can pass that typed view to
`export_markdown_role_spans(spans)` when JSON is needed.

The current supported role shapes are heading markers and text, unordered and
ordered list markers and plain list content, fenced-code delimiters and code
content, inline-code delimiters and content, bold/italic delimiters and
content, link label text, link punctuation, balanced link destinations, and
source-backed parser recovery errors. Nested inline nodes take precedence over
their enclosing heading, list, or link context. Link destination classification
uses ordered CST elements, so balanced inner parentheses remain destinations
while only the outer parentheses are punctuation.

Unmatched emphasis markers are valid literal text and therefore do not receive
an error role; genuine parser recovery such as an unclosed link remains
error-shaped.

Trivia, EOF, and ordinary unclassified paragraph text are omitted. The
projector assigns no roles to HTML blocks, thematic breaks, or block-quote
markers. Block quotes remain transparent containers: supported descendants,
such as a nested heading, still produce their normal roles without acquiring a
block-quote role. This prototype does not infer or create diagnostics: the
current Markdown grammar preserves some recovered forms without reporting
them, and parser diagnostics remain a separate current-state view on
`parser.diagnostics()`. Diagnostic policy is a separate CommonMark-aware task.

```mbt check
///|
test "quick start: parser-backed Markdown role spans" {
  let source_id = @core.SourceId("markdown-readme-role-spans")
  let parser = @loom.new_syntax_parser(
    source_id,
    "[text](page_(C).html)\n",
    markdown_grammar.to_syntax_grammar(),
  )
  let attachment = attach_markdown_role_spans(parser)
  let spans = attachment.spans()
  inspect(spans.length() > 0, content="true")
  inspect(spans[0].role() == Punctuation, content="true")
  inspect(
    export_markdown_role_spans(spans).stringify().contains("\"role\""),
    content="true",
  )
  attachment.dispose()
}
```

Keep `MarkdownRole`, `project_markdown_roles`, and
`MarkdownRoleSpansAttachment` local to this example. Consumers observe typed
spans through the projector or attachment and cannot construct them; JSON is
an explicit one-way export via `export_markdown_role_spans(spans)`. The
`{start,end,role}` shape validates parent context; Markdown additionally needs
ordered links and nested precedence. Do not introduce a shared role or
role-span API yet.

The stateless compatibility lexer can be wrapped for isolated experiments.
Production mode-aware lexing is wired via the session-owning `mode_relex`
factory in `grammar.mbt` and `Grammar::new`:

```mbt nocheck
///|
let mode_factory : @core.ModeRelexFactory[Token] = @core.erase_mode_lexer_factory(
  new_markdown_mode_lexer,
  EOF,
  error_token=Error("lex error"),
  error_token_from_message=Some(msg => Error(msg)),
)

///|
pub let markdown_grammar : @loom.Grammar[Token, SyntaxKind, Block] = @loom.Grammar::new(
  spec=markdown_spec,
  lex=lex_for_grammar,
  fold_node=markdown_fold_node,
  mode_relex=Some(mode_factory),
)
```

`MarkdownLexMode` tracks whether the lexer is at a line start, inside
inline text, or inside a fenced code block (carrying the open fence
length and fence character):

```mbt nocheck
///|
pub(all) enum MarkdownLexMode {
  LineStart
  Inline
  CodeBlock(Int, Char)
}
```

`markdown_lex_step(source, offset, mode)` returns `(LexStep[Token],
MarkdownLexMode)` — the next token plus the mode to use for the
following token. This is the stateless compatibility API.

For repeated detached stepping, use an opaque `MarkdownLexSession`. It owns
replay and line-fact caches for one lexer lifecycle without changing token
semantics:

```mbt nocheck
///|
let session = MarkdownLexSession()
let (step, next_mode) = session.step(source, offset, mode)
```

A session automatically invalidates source-derived state when the source
changes. Call `session.reset()` when the caller explicitly ends a lifecycle.
Do not share a session between independent source streams.

## AST

Two levels:

```mbt nocheck
///|
pub(all) enum Block {
  Document(Array[Block])
  Heading(Int, Array[Inline])
  Paragraph(Array[Inline])
  UnorderedList(Array[Block])
  OrderedList(Array[Block], OrderedListMarker?)
  UnorderedListItem(Array[Inline])
  OrderedListItem(Array[Inline], OrderedListMarker?)
  CodeBlock(String, String) // (language, content)
  Error(String)
} derive(Eq, Debug)

///|
pub(all) enum Inline {
  Text(String)
  Bold(Array[Inline])
  Italic(Array[Inline])
  InlineCode(String)
  Link(Array[Inline], String) // (text, url)
  Error(String)
} derive(Eq, Debug)
```

Both implement `Show`, `@core.Renderable`, and `@core.TreeNode`.

For ordered lists, the container marker records the opening marker for the list
and each `OrderedListItem` records its own source marker. When both are present,
the item marker is the authoritative per-line source; the container marker is a
fallback for rendering or constructing items without their own marker.

## Running

```bash
cd examples/markdown
moon test    # parser, lexer, mode-lexer, error recovery, source fidelity
             # — includes doctested Quick Start from this README
```

## Learn More

- [`@loom` Quick Start](../../loom/README.md#quick-start) — consumer-side
  flow including `apply_edit`
- [Architecture overview](../../docs/architecture/overview.md) — layer
  diagram and design principles
- [Markdown IR architecture](../../docs/architecture/markdown-ir.md) — IR
  lowering policy and validation expectations
- [`examples/json`](../json/) — step-based total lexing + `block_reparse_spec`
- [`examples/lambda`](../lambda/) — typed `SyntaxNode` views
