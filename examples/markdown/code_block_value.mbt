///|
fn syntax_root(node : @seam.SyntaxNode) -> @seam.SyntaxNode {
  for current = node {
    match current.parent() {
      Some(parent) => continue parent
      None => break current
    }
  }
}

///|
fn list_item_marker_token(node : @seam.SyntaxNode) -> @seam.SyntaxToken? {
  match node.direct_token_of_kind(ListMarkerToken.to_raw()) {
    Some(marker) => Some(marker)
    None => node.direct_token_of_kind(OrderedListMarkerToken.to_raw())
  }
}

///|
fn list_item_content_column_from_node(
  node : @seam.SyntaxNode,
  source : String,
) -> Int? {
  guard list_item_marker_token(node) is Some(marker) else { return None }
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(marker.kind())
  let ordered = match kind {
    OrderedListMarkerToken => true
    _ => false
  }
  guard list_marker_body_end_offset(marker.text(), ordered~) is Some(body_end) else {
    return None
  }
  let body_end_offset = marker.start() + body_end
  let body_end_col = visual_column_at_offset(source, body_end_offset)
  let line_end = line_end_offset(source, body_end_offset, source.length())
  if source[body_end_offset:line_end].is_blank() {
    return Some(body_end_col + 1)
  }
  let (_, content_col) = leading_indent_end_offset_and_column(
    source, body_end_offset, body_end_col,
  )
  let padding = content_col - body_end_col
  if padding == 0 {
    Some(body_end_col + 1)
  } else if padding <= 4 {
    Some(body_end_col + padding)
  } else {
    Some(body_end_col + 1)
  }
}

///|
fn block_quote_content_column_from_node(
  node : @seam.SyntaxNode,
  source : String,
) -> Int? {
  guard node.direct_token_of_kind(BlockQuoteMarkerToken.to_raw())
    is Some(marker) else {
    return None
  }
  let text = marker.text()
  guard block_quote_marker_gt_offset(text) is Some(gt_offset) else {
    return None
  }
  let body_end_col = visual_column_at_offset(
    source,
    marker.start() + gt_offset + 1,
  )
  if gt_offset + 1 < text.length() {
    Some(body_end_col + 1)
  } else {
    Some(body_end_col)
  }
}

///|
fn nearest_container_content_column(
  node : @seam.SyntaxNode,
  source : String,
) -> Int {
  for current = node.parent() {
    match current {
      Some(parent) => {
        let kind : SyntaxKind = @seam.FromRawKind::from_raw(parent.kind())
        match kind {
          ListItemNode =>
            match list_item_content_column_from_node(parent, source) {
              Some(col) => break col
              None => continue parent.parent()
            }
          BlockQuoteNode =>
            match block_quote_content_column_from_node(parent, source) {
              Some(col) => break col
              None => continue parent.parent()
            }
          _ => continue parent.parent()
        }
      }
      None => break 0
    }
  }
}

///|
fn strip_indented_code_line(
  node : @seam.SyntaxNode,
  source : String,
  first_token : @seam.SyntaxToken,
  text : String,
) -> String {
  let token_col = visual_column_at_offset(source, first_token.start())
  let required_col = nearest_container_content_column(node, source) + 4
  strip_visual_columns(text, token_col, (required_col - token_col).max(0))
}

///|
fn trim_code_boundary_newlines(value : String, fenced~ : Bool) -> String {
  let without_leading = if value.has_prefix("\n") {
    value[1:].to_owned()
  } else {
    value
  }
  if fenced {
    if without_leading.has_suffix("\n") {
      without_leading[:without_leading.length() - 1].to_owned()
    } else {
      without_leading
    }
  } else {
    // Blank lines after an indented-code line terminate the block but are not
    // part of its value; fenced blocks preserve their final content newline.
    without_leading.trim_end(chars="\n".view()).to_owned()
  }
}

///|
fn fenced_code_block_value(node : @seam.SyntaxNode) -> String {
  let buf = StringBuilder::StringBuilder()
  let mut in_code = false
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          CodeFenceOpenToken => in_code = true
          CodeFenceCloseToken => in_code = false
          CodeTextToken if in_code => buf.write_string(token.text())
          NewlineToken | BlankLineToken if in_code => buf.write_string("\n")
          _ => ()
        }
      }
      _ => ()
    }
  }
  trim_code_boundary_newlines(buf.to_string(), fenced=true)
}

///|
fn indented_code_block_value(
  node : @seam.SyntaxNode,
  source : String,
) -> String {
  let buf = StringBuilder::StringBuilder()
  let line_parts : Array[String] = []
  let mut first_indented_token : @seam.SyntaxToken? = None
  let mut in_code = false
  fn flush_indented_line() -> Unit {
    match first_indented_token {
      Some(token) => {
        buf.write_string(
          strip_indented_code_line(node, source, token, line_parts.join("")),
        )
        line_parts.clear()
        first_indented_token = None
      }
      None => ()
    }
  }
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          IndentationToken => {
            in_code = true
            if first_indented_token is None {
              first_indented_token = Some(token)
            }
            line_parts.push(token.text())
          }
          NewlineToken | BlankLineToken if in_code => {
            flush_indented_line()
            buf.write_string("\n")
          }
          _ if first_indented_token is Some(_) => line_parts.push(token.text())
          _ => ()
        }
      }
      _ => ()
    }
  }
  flush_indented_line()
  trim_code_boundary_newlines(buf.to_string(), fenced=false)
}

///|
fn code_block_value_with_source(
  node : @seam.SyntaxNode,
  source : String,
) -> String {
  if node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) is Some(_) {
    fenced_code_block_value(node)
  } else {
    indented_code_block_value(node, source)
  }
}

///|
/// Demand-driven compatibility boundary for callers that only own a syntax
/// node. Fenced blocks never invoke `load_source`; indented blocks invoke it
/// exactly once. Top-level lowering paths should prefer
/// `code_block_value_with_source` and supply their existing source snapshot.
fn code_block_value_with_source_loader(
  node : @seam.SyntaxNode,
  load_source : () -> String,
) -> String {
  if node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) is Some(_) {
    fenced_code_block_value(node)
  } else {
    indented_code_block_value(node, load_source())
  }
}

///|
fn code_block_value(node : @seam.SyntaxNode) -> String {
  code_block_value_with_source_loader(node, fn() { syntax_root(node).text() })
}
