# `dowdiness/jsx`

Simplified JSX parser example for [`dowdiness/loom`](../../loom/), designed
for **streaming prefixes**: an LLM emits JSX-like markup token by token, and
every prefix — including cuts mid-tag-name, mid-string, or mid-expression —
must parse to a tree that keeps all already-seen content, so a UI can grow
incrementally without losing node identity.

Implements Phase 1 of canopy's JSX incremental-parser plan
(`docs/plans/2026-07-09-jsx-incremental-parser-generative-ui.md` in the
canopy repository; the error-recovery design was validated over two external
review rounds before implementation).

## Scope

**This is a simplified JSX grammar, not a JavaScript parser.** `{...}`
expression content is scanned opaquely (brace-depth tracked,
string-literal-aware) and lands in the AST as raw text.

Correctly handles:
- Elements, fragments (`<>...</>`), self-closing tags
- Attributes: `name`, `name="str"` / `name='str'`, `name={expr}`
- `{expr}` children, with nested braces and quoted strings inside
- Every EOF-truncation shape: mid-tag-name, mid-attribute-string,
  mid-expression, mid-expression-string — content is preserved as normal
  tokens and the truncated tree is shape-identical to its closed equivalent
- Mismatched close tags (html-style unwind to the matching ancestor)

Out of scope (Phase 1 limitations, recorded in the canopy plan):
- Nested JSX inside `{...}` (e.g. `.map()`-driven list rendering) — the
  expression stays one opaque span
- Template-literal `${}` nesting, comments, and regex literals inside
  expressions (can mis-balance brace depth)
- Entity references and text-level escaping of `<` / `{`

## Public API

```mbt nocheck
pub let jsx_grammar : @loom.Grammar[@token.Token, @syntax.SyntaxKind, JsxNode]
pub fn parse_cst(String) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError
pub fn parse_ast(String) -> (JsxNode, @core.DiagnosticSet) raise @core.LexError
pub(all) enum JsxNode { Root(..); Element(..); Fragment(..); Text(..); ExprSpan(..); Error(..) }
```

`JsxNode` implements `TreeNode` (reconciliation: `same_kind` is
tag-sensitive for elements, content-insensitive for text/expressions so a
growing span keeps its projection identity) and `Renderable` (normalized
`unparse`).

## Examples

```mbt check
///|
test "parse a closed tree" {
  let (_, diagnostics) = parse_ast("<div class=\"foo\"><p>hi{x}</p></div>")
  inspect(diagnostics.length(), content="0")
}

///|
test "a truncated streaming prefix keeps its children" {
  let (ast, diagnostics) = parse_ast("<div><span>text")
  inspect(diagnostics.length(), content="2")
  @debug.assert_eq(
    ast,
    JsxNode::Root(children=[
      JsxNode::Element(tag="div", attrs=[], children=[
        JsxNode::Element(tag="span", attrs=[], children=[JsxNode::Text("text")]),
      ]),
    ]),
  )
}

///|
test "a truncated expression is diagnosed, not discarded" {
  let (ast, _) = parse_ast("<p>{foo.bar(")
  guard ast is Root(children=[Element(children=[ExprSpan(raw~)], ..)]) else {
    fail("unexpected shape")
  }
  inspect(raw, content="foo.bar(")
}
```
