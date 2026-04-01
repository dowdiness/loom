///|
/// Convert the inline children of a node to an Array[Inline].
/// `skip_kind` optionally specifies a delimiter token kind to skip
/// (e.g., StarStarToken inside BoldNode, StarToken inside ItalicNode).
fn convert_inline_children_skip(
  node : @seam.SyntaxNode,
  skip_kind : SyntaxKind?,
) -> Array[Inline] {
  let inlines : Array[Inline] = []
  for elem in node.all_children() {
    match elem {
      @seam.SyntaxElement::Token(tok) => {
        let tok_kind : SyntaxKind = @seam.FromRawKind::from_raw(tok.kind())
        if skip_kind is Some(k) && tok_kind == k {
          continue
        }
        match tok_kind {
          TextToken => inlines.push(Inline::Text(tok.text()))
          // Skip structural tokens (HeadingMarker, ListMarker, Newline, etc.)
          HeadingMarkerToken
          | ListMarkerToken
          | NewlineToken
          | BlankLineToken
          | EofToken
          | CodeFenceOpenToken
          | CodeFenceCloseToken
          | CodeTextToken => ()
          // Orphan delimiters in error recovery get rendered as text
          StarToken => inlines.push(Inline::Text("*"))
          StarStarToken => inlines.push(Inline::Text("**"))
          BacktickToken => inlines.push(Inline::Text("`"))
          LeftBracketToken => inlines.push(Inline::Text("["))
          RightBracketToken => inlines.push(Inline::Text("]"))
          LeftParenToken => inlines.push(Inline::Text("("))
          RightParenToken => inlines.push(Inline::Text(")"))
          ErrorToken | ErrorNode => inlines.push(Inline::Text(tok.text()))
          _ => ()
        }
      }
      @seam.SyntaxElement::Node(child) => convert_inline_node(child, inlines)
    }
  }
  inlines
}

///|
/// Convert the inline children of a node to an Array[Inline].
/// No delimiter tokens are skipped.
fn convert_inline_children(node : @seam.SyntaxNode) -> Array[Inline] {
  convert_inline_children_skip(node, None)
}

///|
/// Convert an inline CST node to Inline values and push into the inlines array.
fn convert_inline_node(
  child : @seam.SyntaxNode,
  inlines : Array[Inline],
) -> Unit {
  let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
  match child_kind {
    BoldNode => {
      // Skip StarStarToken delimiters
      let inner = convert_inline_children_skip(child, Some(StarStarToken))
      inlines.push(Inline::Bold(inner))
    }
    ItalicNode => {
      // Skip StarToken delimiters
      let inner = convert_inline_children_skip(child, Some(StarToken))
      inlines.push(Inline::Italic(inner))
    }
    InlineCodeNode => {
      // Collect text inside backticks (skip BacktickToken delimiters)
      let buf = StringBuilder::new()
      for inner_elem in child.all_children() {
        match inner_elem {
          @seam.SyntaxElement::Token(t) => {
            let k : SyntaxKind = @seam.FromRawKind::from_raw(t.kind())
            match k {
              BacktickToken => () // skip delimiters
              _ => buf.write_string(t.text())
            }
          }
          _ => ()
        }
      }
      inlines.push(Inline::InlineCode(buf.to_string()))
    }
    LinkNode => {
      // Extract display text (inside []) and URL (inside ())
      let display : Array[Inline] = []
      let url_buf = StringBuilder::new()
      let mut in_parens = false
      let mut past_bracket = false
      for inner_elem in child.all_children() {
        match inner_elem {
          @seam.SyntaxElement::Token(t) => {
            let k : SyntaxKind = @seam.FromRawKind::from_raw(t.kind())
            match k {
              LeftBracketToken => () // skip [
              RightBracketToken => past_bracket = true
              LeftParenToken => in_parens = true
              RightParenToken => in_parens = false
              TextToken =>
                if in_parens {
                  url_buf.write_string(t.text())
                } else if !past_bracket {
                  display.push(Inline::Text(t.text()))
                }
              _ => ()
            }
          }
          @seam.SyntaxElement::Node(inner_node) =>
            if !past_bracket && !in_parens {
              // Inline markup inside link display text
              convert_inline_node(inner_node, display)
            }
        }
      }
      inlines.push(Inline::Link(display, url_buf.to_string()))
    }
    ErrorNode => {
      // Error recovery node — convert children as inline content
      let inner = convert_inline_children(child)
      for item in inner {
        inlines.push(item)
      }
    }
    _ => ()
  }
}
