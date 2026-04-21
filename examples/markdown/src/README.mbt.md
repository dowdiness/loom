# `dowdiness/markdown`

Markdown parser example for [`dowdiness/loom`](../../loom/).

Demonstrates **mode-aware lexing** — `@core.ModeLexer[Token, Mode]` —
the way to handle languages whose token grammar depends on the current
context (line start vs inline vs inside a fenced code block).

## Public API

```mbt nocheck
// ── Grammar ───────────────────────────────────────────────────────────────────

pub let markdown_grammar    : @loom.Grammar[Token, SyntaxKind, Block]
pub let markdown_spec       : @core.LanguageSpec[Token, SyntaxKind]
pub let markdown_mode_lexer : @core.ModeLexer[Token, MarkdownLexMode]

// ── High-level parsing ────────────────────────────────────────────────────────

pub fn parse(String) -> Block                                              // lex errors fold into Block::Error
pub fn parse_markdown(String) -> (Block, Array[@core.Diagnostic[Token]])   // returns diagnostics
  raise @core.LexError
pub fn parse_cst(String) -> (@seam.CstNode, Array[@core.Diagnostic[Token]])
  raise @core.LexError

// ── CST → AST ─────────────────────────────────────────────────────────────────

pub fn markdown_fold_node(@seam.SyntaxNode, (@seam.SyntaxNode) -> Block) -> Block

// ── Lexing ────────────────────────────────────────────────────────────────────

pub fn tokenize(String) -> Array[@core.TokenInfo[Token]] raise @core.LexError
pub fn markdown_lex_step(String, Int, MarkdownLexMode)
  -> (@core.LexStep[Token], MarkdownLexMode)
```

Full signatures: [`pkg.generated.mbti`](pkg.generated.mbti).

Note that `parse` is **not** `raise` — lex errors are routed through
`on_lex_error` into `Block::Error`. If you need diagnostics, use
`parse_markdown` instead.

## Grammar

`markdown_grammar` is the single integration surface. Pass it to
[`@loom`](../../loom/) factories:

```mbt check
///|
test "grammar example: imperative parser returns a Block" {
  let imp = @loom.new_imperative_parser("# Hello\n", markdown_grammar)
  let doc = imp.parse()
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
  let doc : Block = parser.runtime().read(parser.ast())
  match doc {
    Document(_) => ()
    _ => abort("expected Document at top level")
  }
}
```

Mode-aware lexing is wired via `mode_relex` on `Grammar::new`:

```mbt nocheck
let mode_state : @core.ModeRelexState[Token] =
  @core.erase_mode_lexer(markdown_mode_lexer, EOF)

pub let markdown_grammar : @loom.Grammar[Token, SyntaxKind, Block] = @loom.Grammar::new(
  spec=markdown_spec,
  tokenize=tokenize_for_grammar,
  fold_node=markdown_fold_node,
  on_lex_error=fn(msg) { Block::Error("lex error: " + msg) },
  error_token=Some(Error("")),
  mode_relex=Some(mode_state),
)
```

`MarkdownLexMode` tracks whether the lexer is at a line start, inside
inline text, or inside a fenced code block (carrying the open fence
length):

```mbt nocheck
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
pub(all) enum Block {
  Document(Array[Block])
  Heading(Int, Array[Inline])
  Paragraph(Array[Inline])
  UnorderedList(Array[Block])
  ListItem(Array[Inline])
  CodeBlock(String, String)   // (language, content)
  Error(String)
} derive(Eq, Debug)

pub(all) enum Inline {
  Text(String)
  Bold(Array[Inline])
  Italic(Array[Inline])
  InlineCode(String)
  Link(Array[Inline], String)  // (text, url)
  Error(String)
} derive(Eq, Debug)
```

Both implement `Show`, `@core.Renderable`, and `@core.TreeNode`.

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
- [`examples/json`](../json/) — step-based `prefix_lexer` +
  `block_reparse_spec`
- [`examples/lambda`](../lambda/) — typed `SyntaxNode` views
