# `dowdiness/html`

Simplified HTML parser example for [`dowdiness/loom`](../../loom/).

Designed to evaluate loomgen's real-world utility for language grammars.
Loomgen handles ~19% of the implementation (enum boilerplate + spec factory);
the remaining ~62% is hand-written Native rules (lexer + tree construction).

## Scope

**This is a simplified tree builder, not a full HTML5 spec parser.**

Correctly handles:
- Void elements (`<br>`, `<img>`, `<input>`, etc.)
- Raw text elements (`<script>`, `<style>`)
- Nested elements with matching close tags
- Self-closing tags (`<br/>`)
- Comments (`<!-- ... -->`) and doctypes (`<!DOCTYPE html>`)
- Attribute values (double and single quoted)

Out of scope:
- Optional closing tags (HTML5 foster parenting)
- Implied elements (`<table>` → `<tbody>` insertion)
- Namespace handling (SVG, MathML)
- Entity references (`&amp;`, `&#123;`)
- Attribute value entity resolution
- Unquoted attribute values

## Public API

```mbt nocheck
// ── Grammar ───────────────────────────────────────────────────────────────────

pub let html_grammar : @loom.Grammar[@token.Token, @syntax.SyntaxKind, Unit]

// ── Parsing ────────────────────────────────────────────────────────────────────

pub fn parse_cst(String) -> (@seam.CstNode, @core.DiagnosticSet)
  raise @core.LexError

// ── Lexing ─────────────────────────────────────────────────────────────────────

pub fn lex(String) -> @core.LexResult[@token.Token]
```

Full signatures: [`pkg.generated.mbti`](pkg.generated.mbti).

## Quick Start

```mbt check
///|
test "parse a simple HTML document" {
  let (tree, _) = html_grammar.parse_cst("<p>hello</p>")
  inspect(@syntax.SyntaxKind::from_raw(tree.kind()), content="RootNode")
}

///|
test "parse nested elements with diagnostics" {
  let (_, diagnostics) = html_grammar.parse_cst("<ul><li>a</li><li>b</li></ul>")
  inspect(diagnostics.length(), content="0")
}

///|
test "parse void element" {
  let (_, diagnostics) = html_grammar.parse_cst("<br>")
  inspect(diagnostics.length(), content="0")
}

///|
test "report mismatched close tag" {
  let (_, diagnostics) = html_grammar.parse_cst("<div></span>")
  inspect(diagnostics.length() >= 1, content="true")
}

///|
test "report unclosed element" {
  let (_, diagnostics) = html_grammar.parse_cst("<div><p>text")
  inspect(diagnostics.length() >= 1, content="true")
}
```

## Loomgen Evaluation

The example was built to measure how much of a real parser loomgen generates vs. what must be hand-written.

| Category | Lines | % | Files |
|----------|-------|---|-------|
| Loomgen annotations (input) | 141 | 19% | `token/token.mbt`, `meta/term_kind.mbt` |
| Loomgen generated | 141 | 19% | `spec.g.mbt`, `syntax/syntax_kind.mbt`, `token/token_impls.g.mbt` |
| Hand-written native | 448 | 62% | `lexer.mbt`, `cst_parser.mbt`, `grammar.mbt`, `html_spec.mbt` |
| **Total (non-test)** | **730** | **100%** | |

**Key insight:** Loomgen eliminates mechanical boilerplate (enum raw-kind numbering, trait impls, spec factory construction) but the core parsing logic — tokenizer and tree construction — remains unavoidably hand-written Native rules.

### What Loomgen Does For You

- Generates `ToRawKind` / `FromRawKind` / `Show` / `IsTrivia` / `IsError` for both `Token` and `SyntaxKind` from `#loom.token` / `#loom.term` annotations
- Maintains raw-kind numbering consistency between token and syntax kinds
- Generates the `LanguageSpec` factory (`make_html_spec`) with correct trivia/error/root configuration
- Re-numbers when variants are added or removed (proven by [SelfClose removal commit](https://github.com/dowdiness/loom/commit/faca0a9))

## Architecture

```
examples/html/
├── moon.mod                        # package manifest
├── moon.pkg                        # root package imports
├── meta/
│   └── term_kind.mbt               # #loom.term enum (loomgen input)
├── token/
│   ├── moon.pkg
│   ├── token.mbt                   # #loom.token enum (loomgen input)
│   └── token_impls.g.mbt           # generated trait impls (loomgen output)
├── syntax/
│   ├── moon.pkg
│   └── syntax_kind.mbt             # generated SyntaxKind (loomgen output)
├── spec.g.mbt                      # generated make_html_spec factory
├── lexer.mbt                       # hand-written peek/advance tokenizer
├── cst_parser.mbt                  # hand-written recursive descent parser
├── grammar.mbt                     # Grammar::new wiring
├── html_spec.mbt                   # LanguageSpec construction
├── lexer_test.mbt                  # 12 lexer tests
└── parser_test.mbt                 # 5 parser tests
```

### Design Decisions

- **Coarse tag tokens:** `OpenTag(String)` emits the entire `<tag attr=val>` construct as a single token. This simplifies the lexer at the cost of incremental reuse granularity (attribute changes re-lex the whole tag).
- **Peek/advance lexer:** HTML tags span multiple characters, so the view-based pattern matching used by the JSON example doesn't apply. The lexer uses `LexCursor::peek()` / `LexCursor::advance_char()` for character-level tokenization.
- **Sub-package split:** `Token` and `SyntaxKind` live in `token/` and `syntax/` sub-packages to leverage loomgen's `token_impls.g.mbt` generation. The enum is `pub(all)` so constructors are accessible from the parent package.
- **No fold node:** `fold_node=(_node, _recurse) => ()` since this example only produces CST, not an AST.

## Regenerating Generated Files

After modifying `token/token.mbt` or `meta/term_kind.mbt`:

```bash
# Step 1: Fresh generate syntax_kind.mbt and token_impls.g.mbt
moon run loomgen --target native -- \
  examples/html/token/token.mbt \
  --term examples/html/meta/term_kind.mbt \
  /tmp/ht-token /tmp/ht-syntax
cp /tmp/ht-syntax/syntax_kind.mbt examples/html/syntax/
cp /tmp/ht-token/token_impls.g.mbt examples/html/token/

# Step 2: Regenerate spec.g.mbt with seed
moon run loomgen --target native -- \
  --seed examples/html/syntax/syntax_kind.mbt --skip-syntax \
  --spec examples/html/spec.g.mbt \
  --language html \
  --syntax-type SyntaxKind \
  --token-qual @token --syntax-qual @syntax \
  examples/html/token/token.mbt \
  --term examples/html/meta/term_kind.mbt \
  /tmp/ht-spec-token /tmp/ht-spec-syntax

# Step 3: Verify
moon check examples/html
moon test examples/html/lexer_test.mbt examples/html/parser_test.mbt
```

## See Also

- [`examples/json`](../json/) — step-based prefix lexer, block reparse spec
- [`examples/lambda`](../lambda/) — reference grammar with typed SyntaxNode views
- [`examples/markdown`](../markdown/) — mode-aware lexing via `ModeLexer`
- [`loomgen`](../../loomgen/) — the code generator used by this example
- [`docs/api/choosing-a-parser.md`](../../docs/api/choosing-a-parser.md) — parser selection guide
