///|
fn inline_text_from_token_kind(kind : SyntaxKind, text : String) -> String? {
  match kind {
    TextToken => Some(strip_backslash_escapes(text))
    ErrorToken | ErrorNode => Some(text)
    StarToken => Some("*")
    StarStarToken => Some("**")
    BacktickToken => Some(text)
    LeftBracketToken => Some("[")
    RightBracketToken => Some("]")
    LeftParenToken => Some("(")
    RightParenToken => Some(")")
    _ => None
  }
}
///|
fn append_literal_backtick_text(
  inlines : Array[Inline],
  text : String,
  preceded_by_escaped_text : Bool,
) -> Unit {
  if preceded_by_escaped_text {
    match inlines.last() {
      Some(Inline::Text(previous)) if previous.length() > 0 => {
        let prefix = previous[:previous.length() - 1].to_owned()
        inlines[inlines.length() - 1] = Inline::Text(prefix + text)
      }
      _ => inlines.push(Inline::Text(text))
    }
  } else {
    inlines.push(Inline::Text(text))
  }
}
///|
fn append_inline_text(inlines : Array[Inline], text : String) -> Unit {
  match inlines.last() {
    Some(Inline::Text(previous)) =>
      inlines[inlines.length() - 1] = Inline::Text(previous + text)
    _ => inlines.push(Inline::Text(text))
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
  let mut preceding_text_ends_escaped = false
  let mut previous_was_escaped_backtick = false
  fn push_inline(item : Inline) -> Unit {
    let was_pending = pending_newline
    if pending_newline {
      // Trim trailing spaces from line before soft break
      match inlines.last() {
        Some(Inline::Text(value)) => {
          let trimmed = value.trim_end(chars=" ".view()).to_owned()
          if trimmed.length() != value.length() {
            inlines[inlines.length() - 1] = Inline::Text(trimmed)
          }
        }
        _ => ()
      }
      match newline_text {
        Some(text) => inlines.push(Inline::Text(text))
        None => ()
      }
      pending_newline = false
    }
    // Trim leading spaces from line after soft break
    let item = if was_pending {
      match item {
        Inline::Text(value) => {
          let trimmed = value.trim_start(chars=" ".view()).to_owned()
          if trimmed.length() != value.length() {
            Inline::Text(trimmed)
          } else {
            item
          }
        }
        _ => item
      }
    } else {
      item
    }
    inlines.push(item)
  }
  for elem in node.all_children() {
    match elem {
      @seam.SyntaxElement::Token(tok) => {
        let tok_kind : SyntaxKind = @seam.FromRawKind::from_raw(tok.kind())
        if skip_kind is Some(k) && tok_kind == k {
          preceding_text_ends_escaped = false
          previous_was_escaped_backtick = false
          continue
        }
        match tok_kind {
          TextToken => {
            let text = strip_backslash_escapes(tok.text())
            if previous_was_escaped_backtick {
              append_inline_text(inlines, text)
            } else {
              push_inline(Inline::Text(text))
            }
            preceding_text_ends_escaped = text_ends_with_odd_backslashes(
              tok.text(),
            )
            previous_was_escaped_backtick = false
          }
          BacktickToken => {
            let escaped = preceding_text_ends_escaped
            if escaped {
              append_literal_backtick_text(inlines, tok.text(), true)
            } else {
              push_inline(Inline::Text(tok.text()))
            }
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = escaped
          }
          HeadingMarkerToken
          | ListMarkerToken
          | OrderedListMarkerToken
          | BlankLineToken
          | EofToken
          | CodeFenceOpenToken
          | CodeFenceCloseToken
          | CodeTextToken => {
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = false
          }
          NewlineToken => {
            pending_newline = newline_text is Some(_)
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = false
          }
          _ => {
            match inline_text_from_token_kind(tok_kind, tok.text()) {
              Some(text) => push_inline(Inline::Text(text))
              None => ()
            }
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = false
          }
        }
      }
      @seam.SyntaxElement::Node(child) => {
        preceding_text_ends_escaped = false
        previous_was_escaped_backtick = false
        let was_pending = pending_newline
        if pending_newline {
          // Trim trailing spaces from line before soft break
          match inlines.last() {
            Some(Inline::Text(value)) => {
              let trimmed = value.trim_end(chars=" ".view()).to_owned()
              if trimmed.length() != value.length() {
                inlines[inlines.length() - 1] = Inline::Text(trimmed)
              }
            }
            _ => ()
          }
          match newline_text {
            Some(text) => inlines.push(Inline::Text(text))
            None => ()
          }
          pending_newline = false
        }
        let before = inlines.length()
        convert_inline_node(child, inlines)
        // Trim leading spaces from first child after soft break
        if was_pending && inlines.length() > before {
          match inlines[before] {
            Inline::Text(value) => {
              let trimmed = value.trim_start(chars=" ".view()).to_owned()
              if trimmed.length() != value.length() {
                inlines[before] = Inline::Text(trimmed)
              }
            }
            _ => ()
          }
        }
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
  let mut preceding_text_ends_escaped = false
  let mut previous_was_escaped_backtick = false
  fn flush_newline() -> Unit {
    if pending_newline {
      // Trim trailing spaces from line before soft break
      match inlines.last() {
        Some(Inline::Text(value)) => {
          let trimmed = value.trim_end(chars=" ".view()).to_owned()
          if trimmed.length() != value.length() {
            inlines[inlines.length() - 1] = Inline::Text(trimmed)
          }
        }
        _ => ()
      }
      inlines.push(Inline::Text(newline_text))
      pending_newline = false
    }
  }
  for elem in node.direct_elements_iter() {
    match elem {
      @seam.SyntaxElement::Token(tok) => {
        let tok_kind : SyntaxKind = @seam.FromRawKind::from_raw(tok.kind())
        match tok_kind {
          NewlineToken => {
            pending_newline = true
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = false
          }
          TextToken => {
            let was_pending = pending_newline
            flush_newline()
            let text = strip_backslash_escapes(tok.text())
            let text = if was_pending {
              text.trim_start(chars=" ".view()).to_owned()
            } else {
              text
            }
            if previous_was_escaped_backtick {
              append_inline_text(inlines, text)
            } else {
              inlines.push(Inline::Text(text))
            }
            preceding_text_ends_escaped = text_ends_with_odd_backslashes(
              tok.text(),
            )
            previous_was_escaped_backtick = false
          }
          BacktickToken => {
            flush_newline()
            let escaped = preceding_text_ends_escaped
            append_literal_backtick_text(inlines, tok.text(), escaped)
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = escaped
          }
          _ => {
            match inline_text_from_token_kind(tok_kind, tok.text()) {
              Some(text) => {
                let was_pending = pending_newline
                flush_newline()
                let text = if was_pending {
                  text.trim_start(chars=" ".view()).to_owned()
                } else {
                  text
                }
                inlines.push(Inline::Text(text))
              }
              None => ()
            }
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = false
          }
        }
      }
      @seam.SyntaxElement::Node(child) => {
        preceding_text_ends_escaped = false
        previous_was_escaped_backtick = false
        let converted : Array[Inline] = []
        convert_inline_node(child, converted)
        if converted.length() > 0 {
          let was_pending = pending_newline
          flush_newline()
          // Trim leading spaces from first child after soft break
          if was_pending {
            match converted[0] {
              Inline::Text(value) => {
                let trimmed = value.trim_start(chars=" ".view()).to_owned()
                if trimmed.length() != value.length() {
                  converted[0] = Inline::Text(trimmed)
                }
              }
              _ => ()
            }
          }
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
      let (value, _) = lower_code_span(child)
      inlines.push(Inline::InlineCode(value))
    }
    LinkNode => {
      // Extract display text (inside []) and URL (inside ())
      let display : Array[Inline] = []
      let url_buf = StringBuilder::new()
      let mut url_depth = 0
      let mut past_bracket = false
      let mut preceding_text_ends_escaped = false
      let mut previous_was_escaped_backtick = false
      for inner_elem in child.all_children() {
        match inner_elem {
          @seam.SyntaxElement::Token(t) => {
            let k : SyntaxKind = @seam.FromRawKind::from_raw(t.kind())
            match k {
              LeftBracketToken if !past_bracket && url_depth == 0 => {
                preceding_text_ends_escaped = false
                previous_was_escaped_backtick = false
              }
              RightBracketToken if url_depth == 0 => {
                past_bracket = true
                preceding_text_ends_escaped = false
                previous_was_escaped_backtick = false
              }
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
              TextToken if !past_bracket => {
                let text = strip_backslash_escapes(t.text())
                if previous_was_escaped_backtick {
                  append_inline_text(display, text)
                } else {
                  display.push(Inline::Text(text))
                }
                preceding_text_ends_escaped = text_ends_with_odd_backslashes(
                  t.text(),
                )
                previous_was_escaped_backtick = false
              }
              BacktickToken if !past_bracket => {
                let escaped = preceding_text_ends_escaped
                append_literal_backtick_text(display, t.text(), escaped)
                preceding_text_ends_escaped = false
                previous_was_escaped_backtick = escaped
              }
              ErrorToken | ErrorNode if !past_bracket => {
                display.push(Inline::Text(t.text()))
                preceding_text_ends_escaped = false
                previous_was_escaped_backtick = false
              }
              _ => {
                preceding_text_ends_escaped = false
                previous_was_escaped_backtick = false
              }
            }
          }
          @seam.SyntaxElement::Node(inner_node) => {
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = false
            if !past_bracket && url_depth == 0 {
              // Inline markup inside link display text
              convert_inline_node(inner_node, display)
            }
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
