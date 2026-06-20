///|
/// Returns true for tokens that indicate a block boundary.
fn is_block_boundary(token : Token) -> Bool {
  match token {
    HeadingMarker(_)
    | ListMarker
    | OrderedListMarker(_)
    | BlockQuoteMarker
    | CodeFenceOpen(_, _)
    | BlankLine
    | EOF => true
    _ => false
  }
}

///|
/// Root entry point for the Markdown parser.
fn parse_root(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_document(ctx)
}

///|
/// Parse the document: a sequence of blocks until EOF.
fn parse_document(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  while ctx.peek() != EOF {
    parse_block(ctx)
  }
}

///|
/// Parse a single block. Dispatches based on the current token.
fn parse_block(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  match ctx.peek() {
    HeadingMarker(_) => parse_heading(ctx)
    ListMarker => parse_list(ctx)
    OrderedListMarker(_) => parse_ordered_list(ctx)
    BlockQuoteMarker => parse_block_quote(ctx)
    CodeFenceOpen(_, _) => parse_code_block(ctx)
    BlankLine =>
      // Consume blank lines (structural separators)
      ctx.emit_token(BlankLineToken)
    Newline =>
      // Consume stray newlines between blocks
      ctx.emit_token(NewlineToken)
    EOF => ()
    _ => parse_paragraph(ctx)
  }
}

///|
/// Parse a heading: HeadingMarker followed by inline content.
fn parse_heading(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(HeadingNode, fn() {
    ctx.emit_token(HeadingMarkerToken)
    parse_inline_content(ctx)
    // Consume the trailing newline if present
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
  })
}

///|
/// Ordered lists can interrupt paragraphs only when the start number is 1.
/// Other ordered-list-looking lines remain paragraph text after a soft break.
fn token_breaks_paragraph_after_newline(token : Token) -> Bool {
  match token {
    OrderedListMarker(marker) => marker.start() == 1
    _ => is_block_boundary(token)
  }
}

///|
fn parse_paragraph_continuation_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  match ctx.peek() {
    OrderedListMarker(_) => ctx.emit_token(TextToken)
    _ => ()
  }
  parse_inline_content(ctx)
}

///|
/// Parse a paragraph: inline content possibly spanning multiple lines.
/// Continues across Newline tokens if the next token is not a block marker.
fn parse_paragraph(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(ParagraphNode, fn() {
    parse_inline_content(ctx)
    // Multi-line paragraph: continue across newlines if the next token is not a block boundary.
    while ctx.peek() is Newline {
      // Peek ahead: if the token after the newline is a block boundary, stop.
      let next = ctx.peek_nth(1)
      if token_breaks_paragraph_after_newline(next) ||
        next is Newline ||
        next is EOF {
        // End of paragraph — consume the trailing newline.
        ctx.emit_token(NewlineToken)
        break
      }
      // Continue paragraph on next line: consume newline and parse more inline.
      ctx.emit_token(NewlineToken)
      parse_paragraph_continuation_line(ctx)
    }
  })
}

///|
fn token_continues_block_quote_paragraph(token : Token) -> Bool {
  match token {
    Newline | EOF => false
    _ => !token_breaks_paragraph_after_newline(token)
  }
}

///|
fn thematic_break_marker_text(text : String) -> Bool {
  let (count, valid, seen_marker) = for
    ch in text
    marker = (None : Char?),
    count = 0,
    valid = true,
    seen_marker = false,
    indent = 0 {
    if !valid {
      continue marker, count, false, seen_marker, indent
    }
    match ch {
      ' ' =>
        if seen_marker {
          continue marker, count, true, true, indent
        } else if indent < 3 {
          continue marker, count, true, false, indent + 1
        } else {
          continue marker, count, false, false, indent
        }
      '\t' =>
        if seen_marker {
          continue marker, count, true, true, indent
        } else {
          continue marker, count, false, false, indent
        }
      '-' | '_' | '*' =>
        match marker {
          Some(existing) if existing != ch =>
            continue marker, count, false, seen_marker, indent
          _ => continue Some(ch), count + 1, true, true, indent
        }
      _ => continue marker, count, false, seen_marker, indent
    }
  } nobreak {
    (count, valid, seen_marker)
  }
  valid && seen_marker && count >= 3
}

///|
fn line_at_offset_is_thematic_break(
  ctx : @core.ParserContext[Token, SyntaxKind],
  offset : Int,
) -> Bool {
  let line = StringBuilder::new()
  for i = offset {
    match ctx.peek_nth(i) {
      Newline | EOF => break thematic_break_marker_text(line.to_string())
      Text(text) => line.write_string(text)
      Star => line.write_string("*")
      StarStar => line.write_string("**")
      _ => break false
    }
    continue i + 1
  }
}

///|
fn next_unquoted_line_is_thematic_break(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  line_at_offset_is_thematic_break(ctx, 1)
}

///|
fn consume_block_quote_paragraph_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  match ctx.peek_nth(1) {
    BlockQuoteMarker if token_continues_block_quote_paragraph(ctx.peek_nth(2)) => {
      ctx.emit_token(NewlineToken)
      ctx.emit_token(BlockQuoteMarkerToken)
      parse_paragraph_continuation_line(ctx)
      true
    }
    token if !next_unquoted_line_is_thematic_break(ctx) &&
      token_continues_block_quote_paragraph(token) => {
      ctx.emit_token(NewlineToken)
      parse_paragraph_continuation_line(ctx)
      true
    }
    _ => false
  }
}

///|
fn parse_block_quote_paragraph(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  ctx.node(ParagraphNode, fn() {
    parse_inline_content(ctx)
    while ctx.peek() is Newline {
      if !consume_block_quote_paragraph_continuation(ctx) {
        ctx.emit_token(NewlineToken)
        break
      }
    }
  })
}

///|
fn consume_quoted_list_item_separator_if_matching(
  ctx : @core.ParserContext[Token, SyntaxKind],
  matches_marker : (@core.ParserContext[Token, SyntaxKind]) -> Bool,
) -> Bool {
  guard ctx.peek() is Newline && ctx.peek_nth(1) is BlockQuoteMarker else {
    return false
  }
  ctx.emit_token(NewlineToken)
  ctx.emit_token(BlockQuoteMarkerToken)
  while ctx.peek() is BlankLine && ctx.peek_nth(1) is BlockQuoteMarker {
    ctx.emit_token(BlankLineToken)
    ctx.emit_token(BlockQuoteMarkerToken)
  }
  matches_marker(ctx)
}

///|
fn block_quote_list_continuation_matches(
  ctx : @core.ParserContext[Token, SyntaxKind],
  matches_marker : (@core.ParserContext[Token, SyntaxKind]) -> Bool,
) -> Bool {
  let checkpoint = ctx.checkpoint()
  let matches = consume_quoted_list_item_separator_if_matching(
    ctx, matches_marker,
  )
  ctx.restore(checkpoint)
  matches
}

///|
fn parse_block_quote_marker_scoped_list(
  ctx : @core.ParserContext[Token, SyntaxKind],
  list_kind : SyntaxKind,
  marker_matches : (@core.ParserContext[Token, SyntaxKind]) -> Bool,
  parse_item : (@core.ParserContext[Token, SyntaxKind]) -> Unit,
) -> Unit {
  ctx.node(list_kind, fn() {
    while marker_matches(ctx) {
      parse_item(ctx)
      if block_quote_list_continuation_matches(ctx, marker_matches) {
        ignore(
          consume_quoted_list_item_separator_if_matching(ctx, marker_matches),
        )
      } else {
        break
      }
    }
  })
}

///|
fn parse_block_quote_list_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
) -> Unit {
  match current_unordered_list_marker(ctx) {
    Some(opening_marker) =>
      parse_block_quote_marker_scoped_list(
        ctx,
        UnorderedListNode,
        ctx => {
          list_marker_matches_at_min_indent(ctx, opening_marker, min_indent)
        },
        parse_list_item,
      )
    None => ()
  }
}

///|
fn parse_block_quote_list(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_block_quote_list_at_min_indent(ctx, 0)
}

///|
fn parse_block_quote_ordered_list_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
) -> Unit {
  match current_ordered_list_marker(ctx) {
    Some(opening_marker) =>
      parse_block_quote_marker_scoped_list(
        ctx,
        OrderedListNode,
        ctx => {
          ordered_list_marker_matches_at_min_indent(
            ctx, opening_marker, min_indent,
          )
        },
        parse_ordered_list_item,
      )
    None => ()
  }
}

///|
fn parse_block_quote_ordered_list(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  parse_block_quote_ordered_list_at_min_indent(ctx, 0)
}

///|
fn parse_block_quote_after_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  match ctx.peek() {
    HeadingMarker(_) => parse_heading(ctx)
    ListMarker => parse_block_quote_list(ctx)
    OrderedListMarker(_) => parse_block_quote_ordered_list(ctx)
    BlockQuoteMarker => parse_block_quote(ctx)
    CodeFenceOpen(_, _) => parse_code_block(ctx)
    Newline => ctx.emit_token(NewlineToken)
    BlankLine => ctx.emit_token(BlankLineToken)
    EOF => ()
    _ => parse_block_quote_paragraph(ctx)
  }
}

///|
fn consume_block_quote_child_separator(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  if ctx.peek() is Newline && ctx.peek_nth(1) is BlockQuoteMarker {
    ctx.emit_token(NewlineToken)
  }
}

///|
fn parse_block_quote(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(BlockQuoteNode, fn() {
    while ctx.peek() is BlockQuoteMarker {
      ctx.emit_token(BlockQuoteMarkerToken)
      parse_block_quote_after_marker(ctx)
      consume_block_quote_child_separator(ctx)
    }
  })
}

///|
/// Consume the separator after a list item, including blank-line separators
/// that keep the following matching marker in the same loose list.
fn consume_list_item_separator_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : UnorderedListMarker,
  min_indent : Int,
) -> Unit {
  if ctx.peek() is Newline {
    ctx.emit_token(NewlineToken)
  }
  if blank_line_run_is_followed_by_matching_list_marker_at_min_indent(
      ctx, opening_marker, min_indent,
    ) {
    while ctx.peek() is BlankLine {
      ctx.emit_token(BlankLineToken)
    }
  }
}

///|
/// Parse an unordered list: one or more ListItems using the same marker metadata.
fn parse_list(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_list_at_min_indent(ctx, 0)
}

///|
fn parse_list_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
) -> Unit {
  ctx.node(UnorderedListNode, fn() {
    match current_unordered_list_marker(ctx) {
      Some(opening_marker) =>
        while list_marker_matches_at_min_indent(ctx, opening_marker, min_indent) {
          parse_list_item(ctx)
          consume_list_item_separator_at_min_indent(
            ctx, opening_marker, min_indent,
          )
        }
      None => ()
    }
  })
}

///|
fn parse_nested_list_at_current_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
) -> Bool {
  guard current_list_marker_indent(ctx).map_or(false, indent => {
    indent >= content_indent
  }) else {
    return false
  }
  match ctx.peek() {
    ListMarker => {
      parse_list_at_min_indent(ctx, content_indent)
      true
    }
    OrderedListMarker(_) => {
      parse_ordered_list_at_min_indent(ctx, content_indent)
      true
    }
    _ => false
  }
}

///|
fn next_list_marker_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Int? {
  let checkpoint = ctx.checkpoint()
  ctx.emit_token(NewlineToken)
  let indent = match ctx.peek() {
    ListMarker | OrderedListMarker(_) => current_list_marker_indent(ctx)
    _ => None
  }
  ctx.restore(checkpoint)
  indent
}

///|
fn parse_nested_list_item_flow(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
) -> Unit {
  while true {
    match ctx.peek() {
      Newline =>
        if next_list_marker_indent(ctx).map_or(false, indent => {
            indent >= content_indent
          }) {
          ctx.emit_token(NewlineToken)
          ignore(parse_nested_list_at_current_marker(ctx, content_indent))
        } else {
          break
        }
      ListMarker | OrderedListMarker(_) =>
        if !parse_nested_list_at_current_marker(ctx, content_indent) {
          break
        }
      _ => break
    }
  }
}

///|
fn token_has_non_blank_inline_content(token : Token) -> Bool {
  match token {
    Text(text) => direct_list_item_text_has_non_blank_content(text)
    _ => true
  }
}

///|
fn list_item_line_starts_paragraph(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  for i = 0 {
    let token = ctx.peek_nth(i)
    if is_inline_end(token) {
      break false
    }
    if token_has_non_blank_inline_content(token) {
      break true
    }
    continue i + 1
  }
}

///|
fn token_can_start_lazy_list_item_continuation(
  token : Token,
  allow_ordered_marker~ : Bool,
) -> Bool {
  match token {
    Text([' ' | '\t', ..]) => false
    Newline | EOF => false
    OrderedListMarker(_) if allow_ordered_marker =>
      !token_breaks_paragraph_after_newline(token)
    _ => !is_block_boundary(token)
  }
}

///|
fn next_ordered_marker_starts_nested_list(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
) -> Bool {
  match ctx.peek_nth(1) {
    OrderedListMarker(_) =>
      next_list_marker_indent(ctx).map_or(false, indent => {
        indent >= content_indent
      })
    _ => false
  }
}

///|
/// Parse list-item paragraph content, including lazy continuation lines.
fn parse_list_item_inline_content(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
  allow_ordered_marker~ : Bool,
) -> Unit {
  let has_paragraph_content = list_item_line_starts_paragraph(ctx)
  parse_inline_content(ctx)
  while has_paragraph_content && ctx.peek() is Newline {
    let next = ctx.peek_nth(1)
    if allow_ordered_marker &&
      next_ordered_marker_starts_nested_list(ctx, content_indent) {
      break
    }
    if !token_can_start_lazy_list_item_continuation(next, allow_ordered_marker~) {
      break
    }
    ctx.emit_token(NewlineToken)
    parse_paragraph_continuation_line(ctx)
  }
}

///|
/// Parse a single list item: ListMarker followed by inline content.
fn parse_list_item(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(ListItemNode, fn() {
    let content_indent = current_list_marker_token_width(ctx)
    ctx.emit_token(ListMarkerToken)
    parse_list_item_inline_content(
      ctx,
      content_indent,
      allow_ordered_marker=true,
    )
    parse_nested_list_item_flow(ctx, content_indent)
  })
}

///|
/// Parse an ordered list: one or more ListItems using the same delimiter.
fn parse_ordered_list(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_ordered_list_at_min_indent(ctx, 0)
}

///|
fn parse_ordered_list_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
) -> Unit {
  ctx.node(OrderedListNode, fn() {
    match current_ordered_list_marker(ctx) {
      Some(opening_marker) =>
        while ordered_list_marker_matches_at_min_indent(
                ctx, opening_marker, min_indent,
              ) {
          parse_ordered_list_item(ctx)
          consume_ordered_list_item_separator_at_min_indent(
            ctx, opening_marker, min_indent,
          )
        }
      None => ()
    }
  })
}

///|
/// Parse a single ordered list item: OrderedListMarker followed by inline content.
fn parse_ordered_list_item(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  ctx.node(ListItemNode, fn() {
    let content_indent = current_list_marker_token_width(ctx)
    ctx.emit_token(OrderedListMarkerToken)
    parse_list_item_inline_content(
      ctx,
      content_indent,
      allow_ordered_marker=false,
    )
    parse_nested_list_item_flow(ctx, content_indent)
  })
}

///|
/// Parse a fenced code block: CodeFenceOpen, content lines, CodeFenceClose.
fn parse_code_block(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(CodeBlockNode, fn() {
    ctx.emit_token(CodeFenceOpenToken)
    // Consume the newline after the opening fence
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
    // Consume code text and newlines until CodeFenceClose or EOF
    while !(ctx.peek() is CodeFenceClose) && ctx.peek() != EOF {
      match ctx.peek() {
        CodeText(_) => ctx.emit_token(CodeTextToken)
        Newline => ctx.emit_token(NewlineToken)
        BlankLine => ctx.emit_token(BlankLineToken)
        _ =>
          // Unexpected token inside code block — emit as error
          ctx.bump_error()
      }
    }
    // Consume closing fence if present
    if ctx.peek() is CodeFenceClose {
      ctx.emit_token(CodeFenceCloseToken)
    }
    // Consume trailing newline/blank after close fence
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    } else if ctx.peek() is BlankLine {
      ctx.emit_token(BlankLineToken)
    }
  })
}
