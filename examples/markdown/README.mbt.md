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

pub fn parse(String) -> Block                                              // lex errors fold into Block::Error
pub fn parse_markdown(String) -> (Block, @core.DiagnosticSet)   // returns diagnostics
  raise @core.LexError
pub fn parse_cst(String) -> (@seam.CstNode, @core.DiagnosticSet)
  raise @core.LexError

// ── CST → AST ─────────────────────────────────────────────────────────────────

pub fn markdown_fold_node(@seam.SyntaxNode, (@seam.SyntaxNode) -> Block) -> Block

// ── Parser-backed editor role spans ───────────────────────────────────────────

pub fn project_markdown_roles(@seam.SyntaxNode) -> Array[MarkdownRoleSpan]
pub fn export_markdown_role_spans(Array[MarkdownRoleSpan]) -> Json
pub fn attach_markdown_role_spans(@loom.SyntaxParser) -> MarkdownRoleSpansAttachment

// ── Experimental MarkdownIR M1 slice ──────────────────────────────────────────

pub fn experimental_markdown_ir_from_syntax(@seam.SyntaxNode) -> MarkdownIR
pub fn experimental_markdown_ir_from_syntax_with_diagnostics(
  @seam.SyntaxNode, @core.DiagnosticSet
) -> MarkdownIR
pub fn experimental_markdown_ir_to_block(MarkdownIR) -> Block
pub fn experimental_markdown_ir_to_mdast_json(MarkdownIR) -> Json
pub fn experimental_markdown_ir_to_mdast_json_with_positions(MarkdownIR, String) -> Json
pub fn experimental_markdown_ir_preserve_rewrite(MarkdownIR, String) -> String
pub fn experimental_markdown_ir_local_transform_rewrite(
  MarkdownIR, String, target_origin~ : MarkdownIROrigin, replacement_text~ : String
) -> String
pub fn experimental_markdown_ir_canonical_format(MarkdownIR) -> String
pub fn experimental_markdown_ir_to_commonmark_html(MarkdownIR) -> String

// ── Lexing ────────────────────────────────────────────────────────────────────

pub fn tokenize(String) -> Array[@core.TokenInfo[Token]] raise @core.LexError
pub fn markdown_lex_step(String, Int, MarkdownLexMode)
  -> (@core.LexStep[Token], MarkdownLexMode)
```

Full signatures: [`pkg.generated.mbti`](pkg.generated.mbti).

Note that `parse` is **not** `raise` — lexing failures fold into
`Block::Error`, while parser recovery may preserve malformed inline source as
text or error-shaped IR. If you need diagnostics, use `parse_markdown` instead.

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

## Experimental MarkdownIR

The M1 MarkdownIR API is explicitly experimental. It covers the current parser
subset: document, heading, paragraph, unordered list, list item, fenced code,
text, bold, italic, inline code, and link nodes with UTF-16 source origins.
Unsupported Markdown constructs lower to explicit `Unsupported` IR nodes rather
than token/trivia arrays.

Use `experimental_markdown_ir_from_syntax` after `parse_cst` when you need the
IR, then adapt with `experimental_markdown_ir_to_block`, export with
`experimental_markdown_ir_to_mdast_json` or
`experimental_markdown_ir_to_mdast_json_with_positions`, or smoke-test rewriting
with `experimental_markdown_ir_preserve_rewrite`,
`experimental_markdown_ir_local_transform_rewrite`,
`experimental_markdown_ir_canonical_format`, or render CommonMark-style HTML with
`experimental_markdown_ir_to_commonmark_html`. The position-aware mdast export
must receive the exact source string that produced the IR. The established parser
surfaces (`parse`, `parse_markdown`, `parse_cst`, `markdown_grammar`, and
`markdown_fold_node`) remain the compatibility path for the editor-facing
`Block` / `Inline` model.

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
MarkdownIR and calls `experimental_markdown_ir_to_commonmark_html`; it does not
route through mdast. mdast fixture parity proves adapter tree shape, while
CommonMark HTML parity proves rendered behavior and escaping.

For numbered CommonMark fixtures, the pinned
`tools/commonmark-0.31.2-spec.json` file is the sole normative oracle for source
and expected HTML. Its SHA-256 is
`d431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20`.
For emphasis examples 350 through 481,
`tools/commonmark_html_fixture_overrides.json` may only classify a non-pass case
and give its reason; it never replaces or duplicates the official expected
HTML. `tools/update_commonmark_emphasis_fixtures.mjs` combines those two pinned
inputs into `commonmark_emphasis_html_fixture_data_test.mbt`.

The emphasis baseline is 127 pass, 5 xfail, and 0 skip. The optional MoonBit
audit uses a separate diagnostic taxonomy and currently reports those five
cases (475–477 and 480–481) as `mismatch`, not `unsupported-ir`. Pass fixtures
must continue matching the official HTML, while an xfail that starts matching
must be promoted to pass. Fixture metadata records the CommonMark section,
example number, source, expected HTML, and `CommonMarkHtmlPass` /
`CommonMarkHtmlXfail(reason)` / `CommonMarkHtmlSkip(reason)` status.

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

The command reads the pinned `tools/commonmark-0.31.2-spec.json` corpus and
prints pass/fail/skip counts by section plus each example number and category.
Use `-- --spec path/to/spec.json` to audit another local CommonMark spec file.
Third-party parsers are optional comparison signals only: they cannot override
the pinned official source or HTML, and any comparison tool added to this
workflow must use an exact version pin.

## Grammar

`markdown_grammar` is the single integration surface. Pass it to
[`@loom`](../../loom/) factories:

```mbt check
///|
test "grammar example: imperative parser returns a Block" {
  let imp = @loom.new_imperative_parser("# Hello\n", markdown_grammar)
  let doc = imp.parse().ast
  // The top-level Block is always a Document containing the parsed blocks.
  match doc {
    Document(_) => ()
    _ => abort("expected Document at top level")
  }
}

///|
test "grammar example: reactive parser + set_source" {
  let parser = @loom.new_parser("# Hello\n", markdown_grammar)
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
  let parser = @loom.new_syntax_parser(
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

Mode-aware lexing is wired via `mode_relex` on `Grammar::new`:

```mbt nocheck
///|
let mode_factory : @core.ModeRelexFactory[Token] = @core.erase_mode_lexer(
  markdown_mode_lexer,
  EOF,
  error_token=Error("lex error"),
  error_token_from_message=Some(fn(msg) { Error(msg) }),
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
following token.

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
