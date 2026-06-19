///|
/// Returns true for tokens that indicate a block boundary.
fn is_block_boundary(token : Token) -> Bool {
  match token {
    HeadingMarker(_)
    | ListMarker
    | OrderedListMarker(_)
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
/// Consume the separator after a list item, including blank-line separators
/// that keep the following matching marker in the same loose list.
fn consume_list_item_separator(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : UnorderedListMarker,
) -> Unit {
  if ctx.peek() is Newline {
    ctx.emit_token(NewlineToken)
  }
  if blank_line_run_is_followed_by_matching_list_marker(ctx, opening_marker) {
    while ctx.peek() is BlankLine {
      ctx.emit_token(BlankLineToken)
    }
  }
}

///|
/// Parse an unordered list: one or more ListItems using the same marker metadata.
fn parse_list(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(UnorderedListNode, fn() {
    match current_unordered_list_marker(ctx) {
      Some(opening_marker) =>
        while list_marker_matches(ctx, opening_marker) {
          parse_list_item(ctx)
          consume_list_item_separator(ctx, opening_marker)
        }
      None => ()
    }
  })
}

///|
/// Parse a single list item: ListMarker followed by inline content.
fn parse_list_item(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(ListItemNode, fn() {
    ctx.emit_token(ListMarkerToken)
    parse_inline_content(ctx)
  })
}

///|
/// Parse an ordered list: one or more ListItems using the same delimiter.
fn parse_ordered_list(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(OrderedListNode, fn() {
    match current_ordered_list_marker(ctx) {
      Some(opening_marker) =>
        while ordered_list_marker_matches(ctx, opening_marker) {
          parse_ordered_list_item(ctx)
          consume_ordered_list_item_separator(ctx, opening_marker)
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
    ctx.emit_token(OrderedListMarkerToken)
    parse_inline_content(ctx)
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
