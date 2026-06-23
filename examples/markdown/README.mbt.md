# `dowdiness/markdown`

Markdown parser example for [`dowdiness/loom`](../../loom/).

Demonstrates **mode-aware lexing** — `@core.ModeLexer[Token, Mode]` —
the way to handle languages whose token grammar depends on the current
context (line start vs inline vs inside a fenced code block).

## Public API overview

This section highlights the main entry points. Full generated signatures,
including exported type accessors, are in [`pkg.generated.mbti`](pkg.generated.mbti).

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

`commonmark_html_fixture_test.mbt` compares MarkdownIR HTML rendering against a
checked-in subset of official CommonMark 0.31.2 examples embedded in
`commonmark_html_fixture_data_test.mbt`. The harness parses Markdown to
MarkdownIR and calls `experimental_markdown_ir_to_commonmark_html`; it does not
route through mdast. mdast fixture parity proves adapter tree shape, while
CommonMark HTML parity proves rendered behavior and escaping.

Fixture metadata records CommonMark section, example number, source, expected
HTML, and `CommonMarkHtmlPass` / `CommonMarkHtmlXfail(reason)` /
`CommonMarkHtmlSkip(reason)` status. The generated data header summarizes the
current pass/xfail/skip baseline. Normal MoonBit CI remains hermetic: `moon test`
uses checked-in fixture data only and requires no Node, npm, or network access.

To inspect the full CommonMark 0.31.2 corpus without turning it into a CI gate,
run the optional audit command from `examples/markdown`:

```bash
NEW_MOON_MOD=0 moon run src/tools/commonmark_html_audit --target native
```

The command reads the pinned `tools/commonmark-0.31.2-spec.json` corpus and
prints pass/fail/skip counts by section plus each example number and category.
Use `-- --spec path/to/spec.json` to audit another local CommonMark spec file.

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

Mode-aware lexing is wired via `mode_relex` on `Grammar::new`:

```mbt nocheck
///|
let mode_state : @core.ModeRelexState[Token] = @core.erase_mode_lexer(
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
  mode_relex=Some(mode_state),
)
```

`MarkdownLexMode` tracks whether the lexer is at a line start, inside
inline text, or inside a fenced code block (carrying the open fence
length):

```mbt nocheck
///|
pub(all) enum MarkdownLexMode {
  LineStart
  Inline
  CodeBlock(Int)
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
