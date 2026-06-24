///|
fn trim_inline_text_end_before_newline(children : Array[MarkdownIR]) -> Int {
  match children.last() {
    Some({ node: Text(value), origin }) => {
      let hard_break_spaces = value.length() -
        value.trim_end(chars=" ".view()).length()
      let trimmed = value.trim_end(chars=" \t".view())
      let removed = value.length() - trimmed.length()
      if removed > 0 {
        children[children.length() - 1] = MarkdownIR::text(
          trimmed.to_owned(),
          MarkdownIROrigin(start=origin.start(), end=origin.end() - removed),
        )
      }
      hard_break_spaces
    }
    _ => 0
  }
}

///|
fn flush_pending_inline_newline(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  newline_text : String?,
) -> Unit {
  let hard_break_spaces = trim_inline_text_end_before_newline(children)
  if hard_break_spaces >= 2 {
    children.push(
      MarkdownIR::hard_break(
        MarkdownIROrigin(
          start=origin.start() - hard_break_spaces,
          end=origin.end(),
        ),
      ),
    )
  } else {
    match newline_text {
      Some(text) => children.push(MarkdownIR::text(text, origin))
      None => ()
    }
  }
}

///|
fn trim_inline_text_start_after_newline(child : MarkdownIR) -> MarkdownIR {
  match child.node {
    Text(value) => {
      let trimmed = value.trim_start(chars=" \t".view())
      let removed = value.length() - trimmed.length()
      if removed > 0 {
        let origin = child.origin()
        MarkdownIR::text(
          trimmed.to_owned(),
          MarkdownIROrigin(start=origin.start() + removed, end=origin.end()),
        )
      } else {
        child
      }
    }
    _ => child
  }
}

///|
fn lower_inline_children_skip_with_diags(
  node : @seam.SyntaxNode,
  skip_kind : SyntaxKind?,
  newline_text : String?,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> Array[MarkdownIR] {
  let children : Array[MarkdownIR] = []
  let mut pending_newline : MarkdownIROrigin? = None
  fn push_child(child : MarkdownIR) -> Unit {
    let child = match pending_newline {
      Some(origin) => {
        flush_pending_inline_newline(children, origin, newline_text)
        pending_newline = None
        trim_inline_text_start_after_newline(child)
      }
      None => child
    }
    children.push(child)
  }
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        if skip_kind is Some(kind) && token_kind == kind {
          match pending_newline {
            Some(origin) => {
              flush_pending_inline_newline(children, origin, newline_text)
              pending_newline = None
            }
            None => ()
          }
          continue
        }
        match token_kind {
          TextToken =>
            push_child(
              MarkdownIR::text(
                strip_backslash_escapes(token.text()),
                origin_from_token(token),
              ),
            )
          ErrorToken | ErrorNode => {
            let origin = origin_from_token(token)
            push_child(
              MarkdownIR::raw(
                token.text(),
                origin,
                diagnostics_in_origin(origin),
              ),
            )
          }
          NewlineToken => pending_newline = Some(origin_from_token(token))
          HeadingMarkerToken
          | ListMarkerToken
          | OrderedListMarkerToken
          | BlockQuoteMarkerToken
          | ThematicBreakToken
          | BlankLineToken
          | EofToken
          | CodeFenceOpenToken
          | CodeFenceCloseToken
          | CodeTextToken => ()
          _ =>
            match delimiter_text(token_kind) {
              Some(text) =>
                push_child(MarkdownIR::text(text, origin_from_token(token)))
              None => ()
            }
        }
      }
      @seam.SyntaxElement::Node(child_node) =>
        push_child(
          lower_inline_node_with_diags(
            child_node, newline_text, diagnostics_in_origin,
          ),
        )
    }
  }
  children
}

///|
fn lower_inline_children_with_newline_and_diags(
  node : @seam.SyntaxNode,
  newline_text : String,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> Array[MarkdownIR] {
  lower_inline_children_skip_with_diags(
    node,
    None,
    Some(newline_text),
    diagnostics_in_origin,
  )
}

///|
fn lower_direct_inline_token_with_diags(
  token : @seam.SyntaxToken,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR? {
  let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
  match token_kind {
    TextToken =>
      Some(
        MarkdownIR::text(
          strip_backslash_escapes(token.text()),
          origin_from_token(token),
        ),
      )
    ErrorToken | ErrorNode => {
      let origin = origin_from_token(token)
      Some(MarkdownIR::raw(token.text(), origin, diagnostics_in_origin(origin)))
    }
    HeadingMarkerToken
    | ListMarkerToken
    | OrderedListMarkerToken
    | BlockQuoteMarkerToken
    | ThematicBreakToken
    | BlankLineToken
    | NewlineToken
    | EofToken
    | CodeFenceOpenToken
    | CodeFenceCloseToken
    | CodeTextToken => None
    _ =>
      delimiter_text(token_kind).map(text => {
        MarkdownIR::text(text, origin_from_token(token))
      })
  }
}

///|
fn lower_direct_inline_node_with_diags(
  node : @seam.SyntaxNode,
  newline_text : String?,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR? {
  let node_kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match node_kind {
    HeadingNode
    | ParagraphNode
    | UnorderedListNode
    | OrderedListNode
    | HtmlBlockNode
    | ThematicBreakNode
    | CodeBlockNode
    | BlockQuoteNode => None
    _ =>
      Some(
        lower_inline_node_with_diags(node, newline_text, diagnostics_in_origin),
      )
  }
}

///|
fn lower_direct_inline_children_with_newline_and_diags(
  node : @seam.SyntaxNode,
  newline_text : String,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> Array[MarkdownIR] {
  let children : Array[MarkdownIR] = []
  let mut pending_newline : MarkdownIROrigin? = None
  fn push_child(child : MarkdownIR) -> Unit {
    let child = match pending_newline {
      Some(origin) => {
        flush_pending_inline_newline(children, origin, Some(newline_text))
        pending_newline = None
        trim_inline_text_start_after_newline(child)
      }
      None => child
    }
    children.push(child)
  }
  for element in node.direct_elements_iter() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        if token_kind == NewlineToken {
          pending_newline = Some(origin_from_token(token))
        } else {
          match
            lower_direct_inline_token_with_diags(token, diagnostics_in_origin) {
            Some(child) => push_child(child)
            None => ()
          }
        }
      }
      @seam.SyntaxElement::Node(node) =>
        match
          lower_direct_inline_node_with_diags(
            node,
            Some(newline_text),
            diagnostics_in_origin,
          ) {
          Some(child) => push_child(child)
          None => ()
        }
    }
  }
  children
}

///|
fn lower_code_span(node : @seam.SyntaxNode) -> (String, MarkdownIROrigin?) {
  let buf = StringBuilder::new()
  let content_tokens : Array[MarkdownIROrigin] = []
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          BacktickToken => ()
          _ => {
            buf.write_string(token.text())
            content_tokens.push(origin_from_token(token))
          }
        }
      }
      _ => ()
    }
  }
  (buf.to_string(), span_token_origins(content_tokens))
}

///|
fn span_token_origins(origins : Array[MarkdownIROrigin]) -> MarkdownIROrigin? {
  match origins {
    [] => None
    [first, ..] => {
      let last = origins.last().unwrap()
      Some(MarkdownIROrigin(start=first.start(), end=last.end()))
    }
  }
}

///|
fn lower_link_node_with_diags(
  node : @seam.SyntaxNode,
  newline_text : String?,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR {
  let display : Array[MarkdownIR] = []
  let destination_buf = StringBuilder::new()
  let destination_origins : Array[MarkdownIROrigin] = []
  let mut url_depth = 0
  let mut past_bracket = false
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          LeftBracketToken if !past_bracket && url_depth == 0 => ()
          RightBracketToken if url_depth == 0 => past_bracket = true
          LeftParenToken if past_bracket && url_depth == 0 => url_depth = 1
          LeftParenToken if past_bracket => {
            url_depth = url_depth + 1
            destination_buf.write_string(token.text())
            destination_origins.push(origin_from_token(token))
          }
          RightParenToken if url_depth > 1 => {
            url_depth = url_depth - 1
            destination_buf.write_string(token.text())
            destination_origins.push(origin_from_token(token))
          }
          RightParenToken if url_depth == 1 => url_depth = 0
          _ if url_depth > 0 => {
            destination_buf.write_string(token.text())
            destination_origins.push(origin_from_token(token))
          }
          TextToken if !past_bracket =>
            display.push(
              MarkdownIR::text(token.text(), origin_from_token(token)),
            )
          ErrorToken | ErrorNode if !past_bracket => {
            let origin = origin_from_token(token)
            display.push(
              MarkdownIR::raw(
                token.text(),
                origin,
                diagnostics_in_origin(origin),
              ),
            )
          }
          _ => ()
        }
      }
      @seam.SyntaxElement::Node(child_node) =>
        if !past_bracket && url_depth == 0 {
          display.push(
            lower_inline_node_with_diags(
              child_node, newline_text, diagnostics_in_origin,
            ),
          )
        }
    }
  }
  MarkdownIR::link(
    display,
    destination_buf.to_string(),
    origin_from_node(node),
    span_token_origins(destination_origins),
  )
}

///|
fn lower_inline_node_with_diags(
  node : @seam.SyntaxNode,
  newline_text : String?,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    BoldNode => {
      let children = lower_inline_children_skip_with_diags(
        node,
        Some(StarStarToken),
        newline_text,
        diagnostics_in_origin,
      )
      MarkdownIR::bold(
        children,
        origin_from_node(node),
        span_origin_of_children(children),
      )
    }
    ItalicNode => {
      let children = lower_inline_children_skip_with_diags(
        node,
        Some(StarToken),
        newline_text,
        diagnostics_in_origin,
      )
      MarkdownIR::italic(
        children,
        origin_from_node(node),
        span_origin_of_children(children),
      )
    }
    InlineCodeNode => {
      let (value, content_origin) = lower_code_span(node)
      MarkdownIR::inline_code(value, origin_from_node(node), content_origin)
    }
    LinkNode =>
      lower_link_node_with_diags(node, newline_text, diagnostics_in_origin)
    ErrorNode => {
      let origin = origin_from_node(node)
      MarkdownIR::recovered(node.text(), origin, diagnostics_in_origin(origin))
    }
    _ =>
      MarkdownIR::unsupported(
        "unsupported inline node: " + kind.to_string(),
        origin_from_node(node),
      )
  }
}

///|
fn is_setext_heading(node : @seam.SyntaxNode) -> Bool {
  match node.direct_token_of_kind(HeadingMarkerToken.to_raw()) {
    Some(marker) => {
      let marker_start = skip_leading_spaces(marker.text(), 0)
      count_hashes(marker.text(), marker_start) == 0
    }
    None => false
  }
}

///|
/// Trim leading and trailing whitespace from setext heading inline children.
/// CommonMark spec: leading indentation (up to 3 spaces) and trailing
/// whitespace on content lines are not part of the heading's text content.
/// Also adjusts each child's origin so that position-aware consumers (mdast,
/// content-origin) receive ranges that match the trimmed text value.
fn trim_setext_heading_children(
  children : Array[MarkdownIR],
) -> Array[MarkdownIR] {
  let len = children.length()
  if len == 0 {
    return children
  }
  children.mapi((i, child) => {
    match child.node {
      Text(value) => {
        let mut trimmed = value
        let mut origin = child.origin()
        // Trim leading whitespace on first child
        if i == 0 {
          let trimmed_view = value.trim_start(chars=" \t".view())
          let removed = value.length() - trimmed_view.length()
          if removed > 0 {
            trimmed = trimmed_view.to_owned()
            origin = MarkdownIROrigin(
              start=origin.start() + removed,
              end=origin.end(),
            )
          }
        }
        // Trim trailing whitespace on last child
        if i == len - 1 {
          let trimmed_view = trimmed.trim_end(chars=" \t".view())
          let removed = trimmed.length() - trimmed_view.length()
          if removed > 0 {
            trimmed = trimmed_view.to_owned()
            origin = MarkdownIROrigin(
              start=origin.start(),
              end=origin.end() - removed,
            )
          }
        }
        if trimmed.length() != value.length() {
          MarkdownIR::text(trimmed, origin)
        } else {
          child
        }
      }
      _ => child
    }
  })
}

///|
fn heading_depth_from_marker(node : @seam.SyntaxNode) -> Int? {
  match node.direct_token_of_kind(HeadingMarkerToken.to_raw()) {
    Some(marker) => {
      let marker_start = skip_leading_spaces(marker.text(), 0)
      let n = count_hashes(marker.text(), marker_start)
      // count_hashes caps at 6, so n <= 6 is guaranteed.
      if n >= 1 {
        Some(n)
      } else {
        parse_setext_underline_depth(marker.text().view())
      }
    }
    None => None
  }
}

///|
fn lower_paragraph_with_newline_and_diags(
  node : @seam.SyntaxNode,
  newline_text : String,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR {
  let children = normalize_paragraph_boundary_spaces(
    lower_inline_children_with_newline_and_diags(
      node, newline_text, diagnostics_in_origin,
    ),
  )
  MarkdownIR::paragraph(
    children,
    origin_from_node(node),
    span_origin_of_children(children),
  )
}

///|
fn lower_container_child_with_diags(
  child : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  paragraph_newline_text : String,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR? {
  let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
  match child_kind {
    ParagraphNode =>
      Some(
        lower_paragraph_with_newline_and_diags(
          child, paragraph_newline_text, diagnostics_in_origin,
        ),
      )
    HeadingNode
    | BlockQuoteNode
    | UnorderedListNode
    | OrderedListNode
    | CodeBlockNode
    | HtmlBlockNode
    | ThematicBreakNode => Some(recurse(child))
    ErrorNode => {
      let origin = origin_from_node(child)
      Some(
        MarkdownIR::recovered(
          RECOVERED_PARSE_ERROR,
          origin,
          diagnostics_in_origin(origin),
        ),
      )
    }
    _ => None
  }
}

///|
fn list_marker_from_node(node : @seam.SyntaxNode) -> UnorderedListMarker? {
  match node.direct_token_of_kind(ListMarkerToken.to_raw()) {
    Some(marker) => unordered_list_marker_from_text(marker.text())
    None => None
  }
}

///|
fn ordered_list_marker_from_node(node : @seam.SyntaxNode) -> OrderedListMarker? {
  match node.direct_token_of_kind(OrderedListMarkerToken.to_raw()) {
    Some(marker) => ordered_list_marker_from_text(marker.text())
    None => None
  }
}

///|
fn ordered_list_marker_from_ir(ir : MarkdownIR) -> OrderedListMarker? {
  match ir.node {
    OrderedListItem(_, _, _, marker) => marker
    _ => None
  }
}

///|
fn list_item_paragraph_origin(
  node : @seam.SyntaxNode,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIROrigin {
  match content_origin {
    Some(origin) => origin
    None =>
      match node.direct_token_of_kind(ListMarkerToken.to_raw()) {
        Some(marker) => zero_width_origin_at(marker.end())
        None =>
          match node.direct_token_of_kind(OrderedListMarkerToken.to_raw()) {
            Some(marker) => zero_width_origin_at(marker.end())
            None => zero_width_origin_at(node.end())
          }
      }
  }
}

///|
fn trim_list_item_child_paragraph(ir : MarkdownIR) -> MarkdownIR {
  match ir.node {
    Paragraph(children, _) => {
      let trimmed = match children {
        [{ node: Text(value), origin }, ..] => {
          let trimmed_value = value.trim_start(chars=" \t".view())
          let removed = value.length() - trimmed_value.length()
          if removed == 0 {
            children
          } else {
            children.mapi((index, child) => {
              if index == 0 {
                MarkdownIR::text(
                  trimmed_value.to_owned(),
                  MarkdownIROrigin(
                    start=origin.start() + removed,
                    end=origin.end(),
                  ),
                )
              } else {
                child
              }
            })
          }
        }
        _ => children
      }
      MarkdownIR::paragraph(
        trimmed,
        ir.origin(),
        span_origin_of_children(trimmed),
      )
    }
    _ => ir
  }
}

///|
fn append_list_item_flow_block_children(
  node : @seam.SyntaxNode,
  children : Array[MarkdownIR],
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
) -> Unit {
  for child in node.children() {
    let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
    match child_kind {
      ParagraphNode =>
        children.push(trim_list_item_child_paragraph(recurse(child)))
      HeadingNode
      | UnorderedListNode
      | OrderedListNode
      | HtmlBlockNode
      | ThematicBreakNode
      | CodeBlockNode
      | BlockQuoteNode => children.push(recurse(child))
      _ => ()
    }
  }
}

///|
fn markdown_ir_has_non_blank_inline_content(ir : MarkdownIR) -> Bool {
  match ir.node {
    Text(text) => direct_list_item_text_has_non_blank_content(text)
    _ => true
  }
}

///|
fn lower_list_item_flow_children_with_diags(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> (Array[MarkdownIR], MarkdownIROrigin?) {
  let lowered_inline_children = normalize_paragraph_boundary_spaces(
    lower_direct_inline_children_with_newline_and_diags(
      node, "\n", diagnostics_in_origin,
    ),
  )
  let inline_children = retain_direct_list_item_inline_children(
    lowered_inline_children, markdown_ir_has_non_blank_inline_content,
  )
  let content_origin = span_origin_of_children(inline_children)
  let paragraph_origin = list_item_paragraph_origin(node, content_origin)
  let paragraph = trim_list_item_child_paragraph(
    MarkdownIR::paragraph(inline_children, paragraph_origin, content_origin),
  )
  let children = [paragraph]
  append_list_item_flow_block_children(node, children, recurse)
  (children, paragraph.content_origin())
}

///|
fn code_block_info(node : @seam.SyntaxNode) -> String {
  match node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) {
    Some(fence_token) => {
      let text = fence_token.text()
      let i = count_backticks(text, 0)
      if i < text.length() {
        text[i:].to_owned()
      } else {
        ""
      }
    }
    None => ""
  }
}

///|
fn trim_commonmark_leading_indent_spaces(value : String) -> (String, Int) {
  // CommonMark permits up to three literal spaces of block indentation before
  // paragraph/setext heading content. Tabs and four-space indented-code
  // semantics are parser concerns and intentionally stay outside this Slice A
  // MarkdownIR normalization.
  let count = for ch in value; count = 0 {
    match ch {
      ' ' if count < 3 => continue count + 1
      _ => break count
    }
  } nobreak {
    count
  }
  if count == 0 {
    (value, 0)
  } else {
    (value[count:].to_owned(), count)
  }
}

///|
fn trim_commonmark_trailing_spaces(value : String) -> (String, Int) {
  // Setext heading content excludes trailing literal spaces before the newline.
  // Keep this ASCII-space-only so tab handling remains with the later full
  // indentation semantics slice.
  let count = for pos = value.length() - 1, count = 0 {
    guard pos >= 0 else { break count }
    match value.get_char(pos) {
      Some(' ') => continue pos - 1, count + 1
      _ => break count
    }
  }
  if count == 0 {
    (value, 0)
  } else {
    (value[:value.length() - count].to_owned(), count)
  }
}

///|
fn normalize_paragraph_boundary_spaces(
  children : Array[MarkdownIR],
) -> Array[MarkdownIR] {
  let len = children.length()
  if len == 0 {
    return children
  }
  children.mapi((index, child) => {
    match child.node {
      Text(value) => {
        let (trimmed, origin) = if index == 0 {
          let (leading_trimmed, cut) = trim_commonmark_leading_indent_spaces(
            value,
          )
          if cut > 0 {
            (
              leading_trimmed,
              MarkdownIROrigin(
                start=child.origin().start() + cut,
                end=child.origin().end(),
              ),
            )
          } else {
            (value, child.origin())
          }
        } else {
          (value, child.origin())
        }
        let (trimmed, origin) = if index == len - 1 {
          let (trailing_trimmed, cut) = trim_commonmark_trailing_spaces(trimmed)
          if cut > 0 {
            (
              trailing_trimmed,
              MarkdownIROrigin(start=origin.start(), end=origin.end() - cut),
            )
          } else {
            (trimmed, origin)
          }
        } else {
          (trimmed, origin)
        }
        if trimmed.length() == value.length() {
          child
        } else {
          MarkdownIR::text(trimmed, origin)
        }
      }
      _ => child
    }
  })
}

///|
fn trim_trailing_atx_closing_hashes(
  value : String,
  source_text : String,
  source_offset : Int,
  origin_end : Int,
) -> (String, Int) {
  let hash_count = for pos = value.length() - 1, count = 0 {
    guard pos >= 0 else { break count }
    match value.get_char(pos) {
      Some('#') => continue pos - 1, count + 1
      _ => break count
    }
  }
  guard hash_count > 0 else { return (value, 0) }
  let before_hash_pos = value.length() - hash_count
  let space_count = for pos = before_hash_pos - 1, count = 0 {
    guard pos >= 0 else { break count }
    match value.get_char(pos) {
      Some(' ') | Some('\t') => continue pos - 1, count + 1
      _ => break count
    }
  }
  guard origin_end >= source_offset else { return (value, 0) }
  let raw_end = origin_end - source_offset
  let raw_hash_count = for pos = raw_end - 1, count = 0 {
    guard pos >= 0 else { break count }
    match source_text.get_char(pos) {
      Some('#') => continue pos - 1, count + 1
      _ => break count
    }
  }
  guard raw_hash_count > 0 else { return (value, 0) }
  let raw_hash_start = raw_end - raw_hash_count
  // Escaped trailing hashes are content, not an ATX closing sequence. The raw
  // source still contains the backslash while `value` has already been unescaped.
  guard raw_hash_start > 0 else { return (value, 0) }
  match source_text.get_char(raw_hash_start - 1) {
    Some('\\') => (value, 0)
    Some(' ' | '\t') if before_hash_pos == 0 || space_count > 0 => {
      let cut = hash_count + space_count
      (value[:value.length() - cut].to_owned(), cut)
    }
    _ => (value, 0)
  }
}

///|
fn normalize_heading_leading_whitespace(
  children : Array[MarkdownIR],
  trim_all~ : Bool,
) -> Array[MarkdownIR] {
  if !trim_all {
    return normalize_paragraph_boundary_spaces(children)
  }
  match children {
    [{ node: Text(value), origin }, ..] => {
      let trimmed_view = value.trim_start(chars=" \t".view())
      let cut = value.length() - trimmed_view.length()
      if cut == 0 {
        children
      } else {
        children.mapi((index, child) => {
          if index == 0 {
            MarkdownIR::text(
              trimmed_view.to_owned(),
              MarkdownIROrigin(start=origin.start() + cut, end=origin.end()),
            )
          } else {
            child
          }
        })
      }
    }
    _ => children
  }
}

///|
fn normalize_heading_whitespace(
  children : Array[MarkdownIR],
  source_text : String,
  source_offset : Int,
  trim_all_leading~ : Bool,
  skip_closing_hashes? : Bool = false,
) -> Array[MarkdownIR] {
  let leading_normalized = normalize_heading_leading_whitespace(
    children,
    trim_all=trim_all_leading,
  )
  match leading_normalized {
    [.., { node: Text(value), origin }] => {
      let (space_trimmed, space_cut) = trim_commonmark_trailing_spaces(value)
      let trimmed_end = origin.end() - space_cut
      let (trimmed, hash_cut) = if skip_closing_hashes {
        (space_trimmed, 0)
      } else {
        trim_trailing_atx_closing_hashes(
          space_trimmed, source_text, source_offset, trimmed_end,
        )
      }
      let cut = space_cut + hash_cut
      if cut == 0 {
        leading_normalized
      } else {
        let last_index = leading_normalized.length() - 1
        leading_normalized.mapi((index, child) => {
          if index == last_index {
            MarkdownIR::text(
              trimmed,
              MarkdownIROrigin(start=origin.start(), end=origin.end() - cut),
            )
          } else {
            child
          }
        })
      }
    }
    _ => leading_normalized
  }
}

///|
/// Extract concatenated HTML content from an `HtmlBlockNode`, including the
/// opening line, text lines, and interleaved newlines. HTML blocks preserve
/// exact source formatting, so this does not trim leading or trailing newlines.
fn html_block_value(node : @seam.SyntaxNode) -> String {
  let buf = StringBuilder::new()
  let mut in_html = false
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          HtmlBlockOpenToken => {
            in_html = true
            // NB: HtmlBlockOpen text does not include the trailing newline;
            // the lexer emits that separately as a NewlineToken.
            buf.write_string(token.text())
          }
          // Defensive: the parser guarantees HtmlBlockOpenToken is first, so
          // in_html is always true here for well-formed CSTs.
          HtmlTextToken if in_html => buf.write_string(token.text())
          // HTML block parsing emits newline runs as NewlineToken; BlankLineToken
          // remains structural outside code blocks.
          NewlineToken if in_html => buf.write_string("\n")
          _ => ()
        }
      }
      _ => ()
    }
  }
  buf.to_string()
}

///|
fn html_block_content_origin(node : @seam.SyntaxNode) -> MarkdownIROrigin? {
  // Unlike code_block_content_origin, include HtmlBlockOpenToken: HTML blocks
  // have no close fence, and the opening line is content.
  let content_tokens : Array[@seam.SyntaxToken] = Array::new()
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          HtmlBlockOpenToken | HtmlTextToken | NewlineToken =>
            content_tokens.push(token)
          _ => ()
        }
      }
      _ => ()
    }
  }
  span_token_origins(content_tokens.map(origin_from_token))
}

///|
fn code_block_content_origin(node : @seam.SyntaxNode) -> MarkdownIROrigin? {
  // Indented code content is visually deindented using CommonMark tab stops;
  // that mapping is not necessarily a single source slice. Keep local rewrite
  // targets fenced-only until indented-code rewrites can reindent per line.
  guard node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) is Some(_) else {
    return None
  }
  let mut in_code = false
  let content_tokens : Array[@seam.SyntaxToken] = Array::new()
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          CodeFenceOpenToken => in_code = true
          CodeFenceCloseToken => in_code = false
          CodeTextToken if in_code => content_tokens.push(token)
          IndentedCodeTextToken => {
            in_code = true
            content_tokens.push(token)
          }
          NewlineToken | BlankLineToken if in_code => content_tokens.push(token)
          _ => ()
        }
      }
      _ => ()
    }
  }
  let start_offset = if content_tokens.length() > 0 {
    let first_kind : SyntaxKind = @seam.FromRawKind::from_raw(
      content_tokens[0].kind(),
    )
    if first_kind is NewlineToken {
      1
    } else {
      0
    }
  } else {
    0
  }
  let end_offset = if content_tokens.length() > start_offset {
    let last_kind : SyntaxKind = @seam.FromRawKind::from_raw(
      content_tokens[content_tokens.length() - 1].kind(),
    )
    if last_kind is NewlineToken {
      content_tokens.length() - 1
    } else {
      content_tokens.length()
    }
  } else {
    0
  }
  if start_offset < end_offset {
    Some(
      MarkdownIROrigin(
        start=content_tokens[start_offset].start(),
        end=content_tokens[end_offset - 1].end(),
      ),
    )
  } else if content_tokens.length() > start_offset {
    Some(
      MarkdownIROrigin(
        start=content_tokens[start_offset].start(),
        end=content_tokens[start_offset].start(),
      ),
    )
  } else if content_tokens.length() > 0 {
    let last_token = content_tokens[content_tokens.length() - 1]
    Some(MarkdownIROrigin(start=last_token.end(), end=last_token.end()))
  } else {
    match node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) {
      Some(fence_token) =>
        Some(MarkdownIROrigin(start=fence_token.end(), end=fence_token.end()))
      None => None
    }
  }
}

///|
fn lower_list_children(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
) -> Array[MarkdownIR] {
  node
  .children()
  .iter()
  .filter_map(child => {
    let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
    match child_kind {
      ListItemNode => Some(recurse(child))
      _ => None
    }
  })
  .collect()
}

///|
fn lower_block_quote_children(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> Array[MarkdownIR] {
  node
  .children()
  .iter()
  .filter_map(child => {
    match
      lower_container_child_with_diags(
        child, recurse, "\n", diagnostics_in_origin,
      ) {
      Some(ir) => Some(trim_list_item_child_paragraph(ir))
      None => None
    }
  })
  .collect()
}

///|
fn list_spread_from_node(
  node : @seam.SyntaxNode,
  children : Array[MarkdownIR],
) -> Bool {
  node.direct_token_of_kind(BlankLineToken.to_raw()) is Some(_) ||
  children.iter().any(child => child.spread() == Some(true))
}

///|
/// Experimental CstFold algebra for the M1 MarkdownIR slice.
///
/// Covers documents, headings, paragraphs, and text. Other Markdown constructs
/// lower to explicit `Unsupported` IR nodes instead of cloned CST token piles.
fn experimental_markdown_ir_fold_node_with_diags(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    DocumentNode => {
      let children : Array[MarkdownIR] = node
        .children()
        .iter()
        .filter_map(child => {
          lower_container_child_with_diags(
            child, recurse, "\n", diagnostics_in_origin,
          )
        })
        .collect()
      MarkdownIR::document(children, origin_from_node(node))
    }
    HeadingNode => {
      let setext = is_setext_heading(node)
      let children = normalize_heading_whitespace(
        lower_inline_children_with_newline_and_diags(
          node, "\n", diagnostics_in_origin,
        ),
        node.text(),
        node.start(),
        trim_all_leading=!setext,
        skip_closing_hashes=setext,
      )
      let content_children = if setext {
        trim_setext_heading_children(children)
      } else {
        children
      }
      match heading_depth_from_marker(node) {
        Some(depth) =>
          MarkdownIR::heading(
            depth,
            content_children,
            origin_from_node(node),
            span_origin_of_children(content_children),
          )
        None =>
          MarkdownIR::unsupported(
            "invalid heading marker",
            origin_from_node(node),
          )
      }
    }
    ParagraphNode =>
      lower_paragraph_with_newline_and_diags(node, "\n", diagnostics_in_origin)
    BlockQuoteNode =>
      MarkdownIR::block_quote(
        lower_block_quote_children(node, recurse, diagnostics_in_origin),
        origin_from_node(node),
      )
    UnorderedListNode => {
      let children = lower_list_children(node, recurse)
      let marker = match children {
        [first, ..] => first.list_marker()
        [] => None
      }
      MarkdownIR::unordered_list(
        children,
        origin_from_node(node),
        spread=list_spread_from_node(node, children),
        marker~,
      )
    }
    OrderedListNode => {
      let children = lower_list_children(node, recurse)
      let marker = match children {
        [first, ..] => ordered_list_marker_from_ir(first)
        [] => None
      }
      MarkdownIR::ordered_list(
        children,
        origin_from_node(node),
        spread=list_spread_from_node(node, children),
        marker~,
      )
    }
    ListItemNode => {
      let (children, content_origin) = lower_list_item_flow_children_with_diags(
        node, recurse, diagnostics_in_origin,
      )
      let spread = node.direct_token_of_kind(BlankLineToken.to_raw()) is Some(_)
      match ordered_list_marker_from_node(node) {
        Some(marker) =>
          MarkdownIR::ordered_list_item(
            children,
            origin_from_node(node),
            spread~,
            content_origin,
            marker=Some(marker),
          )
        None =>
          MarkdownIR::list_item(
            children,
            origin_from_node(node),
            spread~,
            content_origin,
            marker=list_marker_from_node(node),
          )
      }
    }
    CodeBlockNode =>
      MarkdownIR::code_block(
        code_block_info(node),
        code_block_value(node),
        origin_from_node(node),
        code_block_content_origin(node),
      )
    HtmlBlockNode =>
      MarkdownIR::html_block(
        html_block_value(node),
        origin_from_node(node),
        html_block_content_origin(node),
      )
    ThematicBreakNode => MarkdownIR::thematic_break(origin_from_node(node))
    ErrorNode => {
      let origin = origin_from_node(node)
      MarkdownIR::recovered(
        RECOVERED_PARSE_ERROR,
        origin,
        diagnostics_in_origin(origin),
      )
    }
    _ =>
      MarkdownIR::unsupported(
        "unsupported node: " + kind.to_string(),
        origin_from_node(node),
      )
  }
}

///|
fn experimental_markdown_ir_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
) -> MarkdownIR {
  experimental_markdown_ir_fold_node_with_diags(node, recurse, _ => [])
}

///|
fn diagnostic_primary_overlaps_origin(
  diagnostic : @core.Diagnostic,
  origin : MarkdownIROrigin,
) -> Bool {
  match diagnostic.primary {
    Some(range) =>
      @core.Range::new(range.start().value(), range.end().value()).overlaps(
        @core.Range::new(origin.start(), origin.end()),
      )
    None => false
  }
}

///|
fn diagnostics_in_origin(
  diagnostics : @core.DiagnosticSet,
  origin : MarkdownIROrigin,
) -> Array[@core.Diagnostic] {
  diagnostics
  .items()
  .iter()
  .filter(diagnostic => diagnostic_primary_overlaps_origin(diagnostic, origin))
  .collect()
}

///|
/// Experimental `SyntaxNode -> MarkdownIR` lowering for the M1 slice.
///
/// Built by a direct recursive walk rather than `CstFold` because MarkdownIR
/// stores absolute source origins, and `CstFold` reuses cached results
/// verbatim based on position-independent structural hashes. Using `CstFold`
/// would return stale origins after position-shifting edits. See
/// `docs/decisions/2026-06-16-markdown-ir-performance-policy.md`.
pub fn experimental_markdown_ir_from_syntax(
  root : @seam.SyntaxNode,
) -> MarkdownIR {
  fn lower(node : @seam.SyntaxNode) -> MarkdownIR {
    experimental_markdown_ir_fold_node(node, lower)
  }
  lower(root)
}

///|
pub fn experimental_markdown_ir_from_syntax_with_diagnostics(
  root : @seam.SyntaxNode,
  diagnostics : @core.DiagnosticSet,
) -> MarkdownIR {
  fn lower(node : @seam.SyntaxNode) -> MarkdownIR {
    experimental_markdown_ir_fold_node_with_diags(node, lower, origin => {
      diagnostics_in_origin(diagnostics, origin)
    })
  }
  lower(root)
}
