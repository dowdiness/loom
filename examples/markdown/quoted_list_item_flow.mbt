///|
/// Inspect content only after the enclosing quote's complete physical prefix.
/// Indentation belongs to the list item, not to its paragraph continuation.
fn quoted_list_item_next_line_starts_block(
  ctx : @core.ParserContext[Token, SyntaxKind],
  quote : BlockQuoteLineContext,
) -> Bool {
  ctx.lookahead(() => {
    guard ctx.peek() is Newline else { return false }
    ctx.emit_token(NewlineToken)
    guard consume_block_quote_marker_count(ctx, quote.ownership, quote.depth)
      is Some(_) else {
      return false
    }
    if ctx.peek() is Indentation(_) {
      ctx.emit_token(IndentationToken)
    }
    is_block_boundary(ctx.peek()) ||
    current_line_is_link_reference_definition(ctx)
  })
}

///|
/// Consume quote-owned separators transactionally. A blank quoted line is
/// provisional until the following block meets the item's content indent.
fn consume_quoted_list_item_block_prefix(
  ctx : @core.ParserContext[Token, SyntaxKind],
  quote : BlockQuoteLineContext,
  content_indent : Int,
) -> (Int, Int)? {
  if ctx.peek() is Newline {
    ctx.emit_token(NewlineToken)
  }
  while true {
    guard consume_block_quote_marker_count(ctx, quote.ownership, quote.depth)
      is Some(columns) else {
      return None
    }
    if ctx.peek() is BlankLine {
      ctx.emit_token(BlankLineToken)
      continue
    }
    return if ctx.peek() is Indentation(_) &&
      current_quoted_content_indent(ctx, columns) >= content_indent {
      Some(columns)
    } else {
      None
    }
  }
  None
}

///|
fn parse_quoted_list_item_flow(
  ctx : @core.ParserContext[Token, SyntaxKind],
  item : ListItemFlowContext,
  quote : BlockQuoteLineContext,
) -> Unit {
  while ctx.lookahead(() => {
          consume_quoted_list_item_block_prefix(ctx, quote, item.content_indent)
          is Some(_)
        }) {
    let columns = consume_quoted_list_item_block_prefix(
      ctx,
      quote,
      item.content_indent,
    ).unwrap()
    let indent = current_quoted_content_indent(ctx, columns)
    if indent >= item.content_indent + 4 {
      parse_quoted_indented_code_block_at_min_indent(
        ctx,
        item.content_indent + 4,
        quote,
      )
      continue
    }
    match ctx.peek_nth(1) {
      ListMarker =>
        parse_block_quote_list_at_min_indent(
          ctx,
          item.content_indent,
          columns.0,
          columns.1,
          quote.ownership,
          quote.depth,
        )
      OrderedListMarker(_) =>
        parse_block_quote_ordered_list_at_min_indent(
          ctx,
          item.content_indent,
          columns.0,
          columns.1,
          quote.ownership,
          quote.depth,
        )
      HeadingMarker(_) =>
        parse_heading_with_prefix(ctx, Some(PresentLinePrefix))
      ThematicBreak =>
        parse_thematic_break_with_prefix(ctx, Some(PresentLinePrefix))
      CodeFenceOpen(_, _) =>
        parse_quoted_code_block_with_prefix(
          ctx,
          Some(PresentLinePrefix),
          quote_depth=physical_quote_depth(quote.ownership, quote.depth),
        )
      BlockQuoteMarker =>
        parse_block_quote_with_prefix(
          ctx,
          Some(PresentLinePrefix),
          QuotedListOwned(quote, item.content_indent),
        )
      HtmlBlockOpen(_) =>
        parse_html_block(
          ctx,
          Some(PresentLinePrefix),
          HtmlQuotedListItem(quote, item.content_indent),
        )
      _ if current_line_is_link_reference_definition(ctx) =>
        parse_link_reference_definition(ctx)
      _ =>
        ctx.node(ParagraphNode, fn() {
          ctx.emit_token(IndentationToken)
          parse_list_item_inline_content(
            ctx,
            item.content_indent,
            allow_ordered_marker=item.allow_ordered_marker,
            quote_context=Some(quote),
          )
        })
    }
  }
}
