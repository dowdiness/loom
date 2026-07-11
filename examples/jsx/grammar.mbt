// JSX grammar wiring and CST → JsxNode fold (Task 1.2 Step 5), following
// examples/json's value_convert.mbt pattern: one algebra dispatching on
// SyntaxKind, plus a cache-free local recursion wrapper for the one-shot
// parse_ast entry point.

///|
/// Strip the quotes a lexed attribute-string token carries: always the
/// leading quote, and the trailing one only when the literal actually
/// closed (AttrStringLit vs AttrStringLitUnterminated).
fn attr_string_content(text : String, terminated~ : Bool) -> String {
  let end = if terminated { text.length() - 1 } else { text.length() }
  text[1:end].to_owned()
}

///|
/// Concatenate an ExprSpanNode's expression content: every ExprRawText /
/// ExprStringUnterminated chunk between the braces, in source order. The
/// chunking exists for the parser's diagnostics; the AST re-joins it into
/// one opaque raw string (Design B case 4).
fn expr_span_raw(node : @seam.SyntaxNode) -> String {
  let raw_text = @syntax.SyntaxKind::ExprRawTextToken.to_raw()
  let unterminated = @syntax.SyntaxKind::ExprStringUnterminatedToken.to_raw()
  node
  .tokens()
  .filter(t => t.kind() == raw_text || t.kind() == unterminated)
  .map(t => t.text())
  .join("")
}

///|
fn fold_attr(node : @seam.SyntaxNode) -> JsxAttr {
  let name = node
    .direct_token_of_kind(@syntax.SyntaxKind::AttrNameToken.to_raw())
    .map_or("", t => t.text())
  let value = match
    node.direct_token_of_kind(@syntax.SyntaxKind::AttrStringLitToken.to_raw()) {
    Some(t) =>
      JsxAttrValue::StringLit(attr_string_content(t.text(), terminated=true))
    None =>
      match
        node.direct_token_of_kind(
          @syntax.SyntaxKind::AttrStringLitUnterminatedToken.to_raw(),
        ) {
        Some(t) =>
          JsxAttrValue::StringLit(
            attr_string_content(t.text(), terminated=false),
          )
        None =>
          match
            node.direct_child_of_kind(@syntax.SyntaxKind::ExprSpanNode.to_raw()) {
            Some(expr) => JsxAttrValue::ExprSpan(raw=expr_span_raw(expr))
            None => JsxAttrValue::Bare
          }
      }
  }
  JsxAttr(name~, value~)
}

///|
/// The fold algebra. AttrNodes are folded out of band by fold_attr (they
/// are not JsxNodes); when CstFold's cache warming hands one to this
/// function directly it falls to the catch-all, whose value is cached but
/// never read by any consumer.
fn jsx_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> JsxNode,
) -> JsxNode {
  let attr_kind = @syntax.SyntaxKind::AttrNode.to_raw()
  match @syntax.SyntaxKind::from_raw(node.kind()) {
    @syntax.RootNode => JsxNode::Root(children=node.children().map(recurse))
    @syntax.ElementNode => {
      let tag = node
        .direct_token_of_kind(@syntax.SyntaxKind::TagNameToken.to_raw())
        .map_or("", t => t.text())
      let attrs = node.direct_children_of_kind(attr_kind).map(fold_attr)
      let children = node
        .children()
        .filter(c => c.kind() != attr_kind)
        .map(recurse)
      JsxNode::Element(tag~, attrs~, children~)
    }
    @syntax.FragmentNode =>
      JsxNode::Fragment(children=node.children().map(recurse))
    @syntax.TextLeaf => JsxNode::Text(node.text())
    @syntax.ExprSpanNode => JsxNode::ExprSpan(raw=expr_span_raw(node))
    @syntax.ErrorNode => JsxNode::Error(node.text())
    other => JsxNode::Error("unexpected node kind: " + other.to_string())
  }
}

///|
/// Cache-free recursion wrapper (json's syntax_node_to_json precedent).
fn jsx_fold(node : @seam.SyntaxNode) -> JsxNode {
  jsx_fold_node(node, jsx_fold)
}

///|
/// JSX grammar: tokenizer, parser, and AST fold wired together.
pub let jsx_grammar : @loom.Grammar[@token.Token, @syntax.SyntaxKind, JsxNode] = @loom.Grammar::new(
  spec=jsx_spec,
  lex~,
  fold_node=jsx_fold_node,
  incremental_relex_enabled=false,
  mode_relex=Some(jsx_mode_relex_state),
)

///|
pub fn parse_ast(
  source : String,
) -> (JsxNode, @core.DiagnosticSet) raise @core.LexError {
  let (cst, diagnostics) = jsx_grammar.parse_cst(source)
  (jsx_fold(@seam.SyntaxNode::from_cst(cst)), diagnostics)
}
