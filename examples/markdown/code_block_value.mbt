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
fn blank_line_spaces(text : String) -> String {
  trim_trailing_line_ending(text)
}

///|
/// True when a list item or block quote owns this node. Root fences skip
/// source reconstruction; container-owned fences still need visual columns.
fn code_block_is_owned_by_list_or_quote(node : @seam.SyntaxNode) -> Bool {
  for current = node.parent() {
    match current {
      Some(parent) => {
        let kind : SyntaxKind = @seam.FromRawKind::from_raw(parent.kind())
        match kind {
          ListItemNode | BlockQuoteNode => break true
          _ => continue parent.parent()
        }
      }
      None => break false
    }
  }
}

///|
/// A fence-looking opener is still indented code when it starts at least four
/// columns past the nearest list or block-quote content column. Container-owned
/// fences at 0–3 relative columns stay fenced. Root fences use the indent
/// token width so lowering does not copy the document for every code block
/// (MarkdownIR performance policy: root fences never `load_source`).
fn code_block_is_indented_form_with_source(
  node : @seam.SyntaxNode,
  source : String,
) -> Bool {
  match node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) {
    Some(_) =>
      fenced_code_block_structural_indent(node, source) >=
      nearest_container_content_column(node, source) + 4
    None => true
  }
}

///|
fn code_block_is_indented_form(node : @seam.SyntaxNode) -> Bool {
  match node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) {
    None => true
    Some(_) =>
      if code_block_is_owned_by_list_or_quote(node) {
        code_block_is_indented_form_with_source(
          node,
          code_block_source_with_fallback(node, fn() {
            syntax_root(node).text()
          }),
        )
      } else {
        match node.direct_token_of_kind(IndentationToken.to_raw()) {
          Some(indent) => count_leading_indent(indent.text()) >= 4
          None => false
        }
      }
  }
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
fn fenced_code_block_is_list_owned(node : @seam.SyntaxNode) -> Bool {
  match node.parent() {
    Some(parent) => {
      let kind : SyntaxKind = @seam.FromRawKind::from_raw(parent.kind())
      kind is ListItemNode
    }
    None => false
  }
}

///|
fn fenced_code_block_structural_indent(
  node : @seam.SyntaxNode,
  source : String,
) -> Int {
  match node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) {
    Some(opening) => visual_column_at_offset(source, opening.start())
    None => 0
  }
}

///|
fn fenced_code_block_value(node : @seam.SyntaxNode, source : String) -> String {
  let buf = StringBuilder::StringBuilder()
  let structural_indent = if source.length() > 0 {
    fenced_code_block_structural_indent(node, source)
  } else {
    0
  }
  let mut in_code = false
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          CodeFenceOpenToken => in_code = true
          CodeFenceCloseToken => in_code = false
          CodeTextToken if in_code =>
            if structural_indent == 0 {
              buf.write_string(token.text())
            } else {
              let token_column = visual_column_at_offset(source, token.start())
              buf.write_string(
                strip_visual_columns(
                  token.text(),
                  token_column,
                  (structural_indent - token_column).max(0),
                ),
              )
            }
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
fn indented_code_block_value_with_line_stripper(
  node : @seam.SyntaxNode,
  strip_line : (@seam.SyntaxToken, String) -> String,
) -> String {
  let buf = StringBuilder::StringBuilder()
  let line_parts : Array[String] = []
  let mut first_indented_token : @seam.SyntaxToken? = None
  let mut in_code = false
  fn flush_indented_line() -> Unit {
    match first_indented_token {
      Some(token) => {
        buf.write_string(strip_line(token, line_parts.join("")))
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
          IndentationToken
          | HtmlBlockOpenToken
          | HtmlTextToken
          | CodeFenceOpenToken
          | CodeTextToken
          | CodeFenceCloseToken
          | ListMarkerToken
          | OrderedListMarkerToken
          | StarToken
          | BacktickToken
          | TextToken => {
            in_code = true
            if first_indented_token is None {
              first_indented_token = Some(token)
            }
            line_parts.push(token.text())
          }
          BlankLineToken if in_code => {
            flush_indented_line()
            let spaces = blank_line_spaces(token.text())
            if count_leading_indent(spaces) >= 4 {
              buf.write_string(strip_line(token, spaces))
            }
            buf.write_string("\n")
          }
          NewlineToken if in_code => {
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
fn indented_code_block_value(
  node : @seam.SyntaxNode,
  source : String,
) -> String {
  indented_code_block_value_with_line_stripper(node, fn(token, text) {
    strip_indented_code_line(node, source, token, text)
  })
}

///|
/// Source-free compatibility value for the structurally memoized Block fold.
/// Nested container code blocks are not represented by the legacy Block
/// projection, so treating every visited indented block as root-owned preserves
/// the observable top-level value without making the algebra position-sensitive.
fn indented_code_block_value_without_source(node : @seam.SyntaxNode) -> String {
  indented_code_block_value_with_line_stripper(node, fn(_token, text) {
    strip_visual_columns(text, 0, 4)
  })
}

///|
fn code_block_value_with_source(
  node : @seam.SyntaxNode,
  source : String,
) -> String {
  if code_block_is_indented_form_with_source(node, source) {
    indented_code_block_value(node, source)
  } else {
    fenced_code_block_value(node, source)
  }
}

///|
fn code_block_value_without_source(node : @seam.SyntaxNode) -> String {
  if code_block_is_indented_form(node) {
    indented_code_block_value_without_source(node)
  } else {
    fenced_code_block_value(node, "")
  }
}

///|
/// Demand-driven source-aware boundary for callers that only own a syntax node.
/// Root and blockquote fences never invoke `load_source`; list-owned fences do
/// so only when their source-backed CST cannot provide the source. Indented
/// blocks invoke it exactly once. Direct source-aware lowering should prefer
/// `code_block_value_with_source`; structurally memoized compatibility folds use
/// `code_block_value_without_source`.
fn code_block_value_with_source_loader(
  node : @seam.SyntaxNode,
  load_source : () -> String,
) -> String {
  if !code_block_is_indented_form(node) {
    if fenced_code_block_is_list_owned(node) {
      fenced_code_block_value(
        node,
        code_block_source_with_fallback(node, load_source),
      )
    } else {
      fenced_code_block_value(node, "")
    }
  } else {
    indented_code_block_value(node, load_source())
  }
}

///|
/// Obtain the current owning source from an already source-backed CST token.
///
/// This compatibility boundary is intentionally the only Markdown lowering
/// site that reaches through `unsafe_backing_source`. Generic parser reuse
/// rebases source-backed tokens onto the current source before folding, so an
/// indented block can reuse that owning string without reconstructing the
/// complete syntax root. Synthetic token-only trees retain the explicit
/// reconstruction fallback.
fn code_block_source_with_fallback(
  node : @seam.SyntaxNode,
  reconstruct_source : () -> String,
) -> String {
  match (node.cst_node().first_token(_ => false), node.first_token()) {
    (Some(raw), Some(positioned)) if raw.is_source_backed() => {
      let source = raw.unsafe_backing_source()
      if raw.start_offset() == positioned.start() &&
        raw.end_offset() == positioned.end() &&
        source.length() >= syntax_root(node).end() {
        return source
      }
    }
    _ => ()
  }
  reconstruct_source()
}

///|
#warnings("-unused_value")
fn code_block_value(node : @seam.SyntaxNode) -> String {
  code_block_value_with_source_loader(node, fn() {
    code_block_source_with_fallback(node, fn() { syntax_root(node).text() })
  })
}
