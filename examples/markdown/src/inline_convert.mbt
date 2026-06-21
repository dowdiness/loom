///|
fn inline_text_from_token_kind(kind : SyntaxKind, text : String) -> String? {
  match kind {
    TextToken | ErrorToken | ErrorNode => Some(text)
    StarToken => Some("*")
    StarStarToken => Some("**")
    BacktickToken => Some("`")
    LeftBracketToken => Some("[")
    RightBracketToken => Some("]")
    LeftParenToken => Some("(")
    RightParenToken => Some(")")
    _ => None
  }
}

///|
/// Convert the inline children of a node to an Array[Inline].
/// `skip_kind` optionally specifies a delimiter token kind to skip
/// (e.g., StarStarToken inside BoldNode, StarToken inside ItalicNode).
fn convert_inline_children_skip(
  node : @seam.SyntaxNode,
  skip_kind : SyntaxKind?,
  newline_text : String?,
) -> Array[Inline] {
  let inlines : Array[Inline] = []
  let mut pending_newline = false
  fn push_inline(item : Inline) -> Unit {
    if pending_newline {
      match newline_text {
        Some(text) => inlines.push(Inline::Text(text))
        None => ()
      }
      pending_newline = false
    }
    inlines.push(item)
  }
  for elem in node.all_children() {
    match elem {
      @seam.SyntaxElement::Token(tok) => {
        let tok_kind : SyntaxKind = @seam.FromRawKind::from_raw(tok.kind())
        if skip_kind is Some(k) && tok_kind == k {
          continue
        }
        match tok_kind {
          // Skip structural tokens (HeadingMarker, ListMarker, Newline, etc.)
          HeadingMarkerToken
          | ListMarkerToken
          | OrderedListMarkerToken
          | BlankLineToken
          | EofToken
          | CodeFenceOpenToken
          | CodeFenceCloseToken
          | CodeTextToken => ()
          NewlineToken => pending_newline = newline_text is Some(_)
          _ =>
            match inline_text_from_token_kind(tok_kind, tok.text()) {
              Some(text) => push_inline(Inline::Text(text))
              None => ()
            }
        }
      }
      @seam.SyntaxElement::Node(child) => {
        if pending_newline {
          match newline_text {
            Some(text) => inlines.push(Inline::Text(text))
            None => ()
          }
          pending_newline = false
        }
        convert_inline_node(child, inlines)
      }
    }
  }
  inlines
}

///|
/// Convert the inline children of a node to an Array[Inline].
/// No delimiter tokens are skipped.
fn convert_inline_children(node : @seam.SyntaxNode) -> Array[Inline] {
  convert_inline_children_skip(node, None, None)
}

///|
/// Convert inline children and render line-internal newlines as soft-break text.
fn convert_inline_children_with_newline(
  node : @seam.SyntaxNode,
  newline_text : String,
) -> Array[Inline] {
  convert_inline_children_skip(node, None, Some(newline_text))
}

///|
fn inline_has_non_blank_content(inline : Inline) -> Bool {
  match inline {
    Text(text) => direct_list_item_text_has_non_blank_content(text)
    Bold(_) | Italic(_) | InlineCode(_) | Link(_, _) | Error(_) => true
  }
}

///|
fn convert_direct_inline_children_with_newline(
  node : @seam.SyntaxNode,
  newline_text : String,
) -> Array[Inline] {
  let inlines : Array[Inline] = []
  let mut pending_newline = false
  fn flush_newline() -> Unit {
    if pending_newline {
      inlines.push(Inline::Text(newline_text))
      pending_newline = false
    }
  }
  for elem in node.direct_elements_iter() {
    match elem {
      @seam.SyntaxElement::Token(tok) => {
        let tok_kind : SyntaxKind = @seam.FromRawKind::from_raw(tok.kind())
        match tok_kind {
          NewlineToken => pending_newline = true
          _ =>
            match inline_text_from_token_kind(tok_kind, tok.text()) {
              Some(text) => {
                flush_newline()
                inlines.push(Inline::Text(text))
              }
              None => ()
            }
        }
      }
      @seam.SyntaxElement::Node(child) => {
        let converted : Array[Inline] = []
        convert_inline_node(child, converted)
        if converted.length() > 0 {
          flush_newline()
          inlines.append(converted)
        }
      }
    }
  }
  retain_direct_list_item_inline_children(inlines, inline_has_non_blank_content)
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
      let inner = convert_inline_children_skip(child, Some(StarStarToken), None)
      inlines.push(Inline::Bold(inner))
    }
    ItalicNode => {
      // Skip StarToken delimiters
      let inner = convert_inline_children_skip(child, Some(StarToken), None)
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
      let mut url_depth = 0
      let mut past_bracket = false
      for inner_elem in child.all_children() {
        match inner_elem {
          @seam.SyntaxElement::Token(t) => {
            let k : SyntaxKind = @seam.FromRawKind::from_raw(t.kind())
            match k {
              LeftBracketToken if !past_bracket && url_depth == 0 => () // skip [
              RightBracketToken if url_depth == 0 => past_bracket = true
              LeftParenToken if past_bracket && url_depth == 0 => url_depth = 1
              LeftParenToken if past_bracket => {
                url_depth = url_depth + 1
                url_buf.write_string(t.text())
              }
              RightParenToken if url_depth > 1 => {
                url_depth = url_depth - 1
                url_buf.write_string(t.text())
              }
              RightParenToken if url_depth == 1 => url_depth = 0
              _ if url_depth > 0 => url_buf.write_string(t.text())
              TextToken | ErrorToken | ErrorNode if !past_bracket =>
                display.push(Inline::Text(t.text()))
              _ => ()
            }
          }
          @seam.SyntaxElement::Node(inner_node) =>
            if !past_bracket && url_depth == 0 {
              // Inline markup inside link display text
              convert_inline_node(inner_node, display)
            }
        }
      }
      inlines.push(Inline::Link(display, url_buf.to_string()))
    }
    ErrorNode =>
      // Error recovery node — preserve recovery as an explicit semantic error.
      inlines.push(Inline::Error(child.text()))
    ThematicBreakNode => inlines.push(Inline::Text(child.text()))
    _ => ()
  }
}
