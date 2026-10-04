// Iterative parser for physical lines containing repeated blockquote markers.
// It keeps CST stack depth proportional to syntactic quote depth while reusing
// the ordinary blockquote paragraph and Setext parsing seams.

///|
fn consume_current_block_quote_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
) -> (Int, Int)? {
  if ownership is QuotedListOwned(quote, indent) {
    let checkpoint = ctx.checkpoint()
    if consume_block_quote_marker_count(ctx, quote.ownership, quote.depth)
      is Some(_) {
      if consume_current_block_quote_marker(ctx, ListOwned(indent))
        is Some(columns) {
        return Some(columns)
      }
    }
    ctx.restore(checkpoint)
    return None
  }
  if ctx.peek() is BlockQuoteMarker && !ownership.accepts_marker_indent(0) {
    return None
  }
  if prefixed_block_quote_marker(ctx, ownership) {
    ctx.emit_token(IndentationToken)
  }
  guard ctx.peek() is BlockQuoteMarker else { return None }
  let columns = current_block_quote_marker_columns(ctx)
  ctx.emit_token(BlockQuoteMarkerToken)
  Some(columns)
}

///|
fn consume_block_quote_marker_count(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
  count : Int,
) -> (Int, Int)? {
  let mut content_column = 0
  let mut marker_end_column = 0
  for index = 0; index < count; index = index + 1 {
    let owner = if index == 0 { ownership } else { Root }
    match consume_current_block_quote_marker(ctx, owner) {
      Some((next_content_column, next_marker_end_column)) => {
        content_column = next_content_column
        marker_end_column = next_marker_end_column
      }
      None => return None
    }
  }
  Some((content_column, marker_end_column))
}

///|
fn consume_repeated_nested_block_quote_line_prefix(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
  depth : Int,
) -> (Int, Int)? {
  if ctx.peek() is Newline {
    ctx.emit_token(NewlineToken)
  }
  consume_block_quote_marker_count(ctx, ownership, depth)
}

///|
fn repeated_nested_block_quote_paragraph_starts(
  ctx : @core.ParserContext[Token, SyntaxKind],
  columns : (Int, Int),
) -> Bool {
  // At a block start, every ordered marker can open a list; the paragraph
  // interruption rule (start=1) does not apply. Indented code is also a block.
  if ctx.peek() is OrderedListMarker(_) ||
    (
      ctx.peek() is Indentation(_) &&
      (
        current_quoted_content_indent(ctx, columns) >= 4 ||
        is_block_boundary(ctx.peek_nth(1))
      )
    ) {
    return false
  }
  !current_line_is_link_reference_definition(ctx) &&
  !token_is_inline_end(ctx.peek(), InlineParsePolicy::paragraph())
}

///|
fn next_repeated_nested_block_quote_depth(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
) -> Int {
  ctx.lookahead(() => {
    match ctx.peek() {
      Newline => ctx.emit_token(NewlineToken)
      BlankLine => ctx.emit_token(BlankLineToken)
      _ => ()
    }
    let mut depth = 0
    while consume_current_block_quote_marker(
            ctx,
            if depth == 0 {
              ownership
            } else {
              Root
            },
          )
          is Some(_) {
      depth += 1
    }
    depth
  })
}

///|
fn repeated_nested_block_quote_depth(
  ctx : @core.ParserContext[Token, SyntaxKind],
  prefix : LinePrefix?,
) -> Int? {
  ctx.lookahead(() => {
    match prefix {
      Some(_) => ctx.emit_token(IndentationToken)
      None => ()
    }
    let mut depth = 0
    while consume_current_block_quote_marker(ctx, Root) is Some(_) {
      depth += 1
    }
    if depth > 1 {
      Some(depth)
    } else {
      None
    }
  })
}

///|
priv enum RepeatedNestedBlockQuoteContinuation {
  ContinueNestedMarkers(BlockQuotePrefixOwnership, Int)
  ContinueExistingQuote(BlockContinuationAction)
}

///|
fn repeated_nested_block_quote_paragraph_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
  depth : Int,
) -> ContinuationDecision[RepeatedNestedBlockQuoteContinuation] {
  // An enclosing quote can be explicit while the item's inner quote is lazy.
  // Its marker belongs to the outer container, not to a new root quote.
  if ownership is QuotedListOwned(quote, _) &&
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
      token_continues_paragraph_after_softbreak(ctx.peek())
    }) {
    return Continue(ContinueNestedMarkers(quote.ownership, quote.depth))
  }
  let nested_marker_count = ctx.lookahead(() => {
    guard ctx.peek() is Newline else { return None }
    ctx.emit_token(NewlineToken)
    let marked = ctx.peek() is BlockQuoteMarker ||
      (ctx.peek() is Indentation(_) && ctx.peek_nth(1) is BlockQuoteMarker)
    let mut count = 0
    while count < depth &&
          consume_current_block_quote_marker(
            ctx,
            if count == 0 {
              ownership
            } else {
              Root
            },
          )
          is Some(_) {
      count += 1
    }
    if count == 0 && marked {
      Some(0)
    } else if count > 0 && token_continues_paragraph_after_softbreak(ctx.peek()) {
      Some(count)
    } else {
      None
    }
  })
  match nested_marker_count {
    Some(0) => Stop
    Some(count) => Continue(ContinueNestedMarkers(ownership, count))
    None =>
      match decide_block_quote_paragraph_continuation(ctx) {
        Continue(action) => Continue(ContinueExistingQuote(action))
        Stop => Stop
      }
  }
}

///|
impl InlineContinuationAction for RepeatedNestedBlockQuoteContinuation with fn apply(
  self,
  ctx,
) {
  match self {
    ContinueNestedMarkers(ownership, depth) => {
      guard consume_repeated_nested_block_quote_line_prefix(
          ctx, ownership, depth,
        )
        is Some(_) else {
        abort(
          "nested blockquote continuation marker run changed after lookahead",
        )
      }
    }
    ContinueExistingQuote(action) =>
      InlineContinuationAction::apply(action, ctx)
  }
}

///|
fn repeated_nested_block_quote_decider(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
  depth : Int,
) -> () -> ContinuationDecision[RepeatedNestedBlockQuoteContinuation] {
  () => {
    repeated_nested_block_quote_paragraph_continuation(ctx, ownership, depth)
  }
}

///|
fn parse_repeated_nested_block_quote_paragraph(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
  depth : Int,
) -> Unit {
  parse_block_quote_paragraph_with_continuation(
    ctx,
    repeated_nested_block_quote_decider(ctx, ownership, depth),
  )
}

///|
fn repeated_nested_block_quote_setext_underline_depth(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
  depth : Int,
) -> Int? {
  ctx.lookahead(() => {
    guard ctx.peek() is Newline else { return None }
    guard consume_repeated_nested_block_quote_line_prefix(ctx, ownership, depth)
      is Some(_) else {
      return None
    }
    setext_underline_depth_at_current_line(
      ctx,
      allow_list_marker=true,
      min_indent=0,
    )
  })
}

///|
fn repeated_nested_block_quote_starts_setext_heading(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
  depth : Int,
) -> Bool {
  ctx.lookahead(() => {
    parse_indexed_inline_container_without_continuation(
      ctx,
      InlineParsePolicy::paragraph(),
    )
    repeated_nested_block_quote_setext_underline_depth(ctx, ownership, depth)
    is Some(_)
  })
}

///|
fn consume_repeated_nested_block_quote_setext_underline(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
  depth : Int,
) -> Unit {
  guard consume_repeated_nested_block_quote_line_prefix(ctx, ownership, depth)
    is Some(_) else {
    abort("nested blockquote setext prefix changed after lookahead")
  }
  emit_setext_underline_line(ctx)
}

///|
fn try_parse_repeated_nested_block_quote_setext_heading(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
  depth : Int,
) -> Bool {
  try_parse_block_quote_setext_heading_with_continuation(
    ctx,
    repeated_nested_block_quote_decider(ctx, ownership, depth),
    () => {
      repeated_nested_block_quote_setext_underline_depth(ctx, ownership, depth)
    },
    () => {
      consume_repeated_nested_block_quote_setext_underline(
        ctx, ownership, depth,
      )
    },
  )
}

///|
fn parse_repeated_nested_block_quote_block(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
  depth : Int,
  content_column : Int,
  marker_end_column : Int,
) -> Unit {
  ctx.with_reuse_context(
    block_quote_content_reuse_context(
      ctx, content_column, marker_end_column, depth,
    ),
    fn() {
      if repeated_nested_block_quote_paragraph_starts(
          ctx,
          (content_column, marker_end_column),
        ) {
        if !repeated_nested_block_quote_starts_setext_heading(
            ctx, ownership, depth,
          ) ||
          !try_parse_repeated_nested_block_quote_setext_heading(
            ctx, ownership, depth,
          ) {
          parse_repeated_nested_block_quote_paragraph(ctx, ownership, depth)
        }
      } else {
        parse_block_quote_after_marker(
          ctx, content_column, marker_end_column, ownership, depth,
        )
      }
    },
  )
}

///|
fn parse_repeated_nested_block_quote(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
  depth : Int,
  prefix : LinePrefix?,
) -> Unit {
  ctx.node(BlockQuoteNode, fn() {
    match prefix {
      Some(_) => ctx.emit_token(IndentationToken)
      None => ()
    }
    guard consume_current_block_quote_marker(ctx, Root)
      is Some((first_content_column, first_marker_end_column)) else {
      abort("nested blockquote parser requires an opening marker")
    }
    let mut content_column = first_content_column
    let mut marker_end_column = first_marker_end_column
    for index = 1; index < depth; index = index + 1 {
      ctx.start_node(BlockQuoteNode)
      match consume_current_block_quote_marker(ctx, Root) {
        Some((next_content_column, next_marker_end_column)) => {
          content_column = next_content_column
          marker_end_column = next_marker_end_column
        }
        None => abort("nested blockquote marker depth changed after lookahead")
      }
    }
    let mut open_depth = depth
    parse_repeated_nested_block_quote_block(
      ctx, ownership, open_depth, content_column, marker_end_column,
    )
    while true {
      let next_depth = next_repeated_nested_block_quote_depth(ctx, ownership)
      guard next_depth > 0 else { break }
      while open_depth > next_depth {
        ctx.finish_node()
        open_depth -= 1
      }
      match ctx.peek() {
        Newline => ctx.emit_token(NewlineToken)
        BlankLine => ctx.emit_token(BlankLineToken)
        _ => ()
      }
      let preserved_depth = open_depth
      let mut next_content_column = 0
      let mut next_marker_end_column = 0
      for marker_index = 0
          marker_index < next_depth
          marker_index = marker_index + 1 {
        if marker_index >= preserved_depth {
          ctx.start_node(BlockQuoteNode)
          open_depth += 1
        }
        match
          consume_current_block_quote_marker(
            ctx,
            if marker_index == 0 {
              ownership
            } else {
              Root
            },
          ) {
          Some((line_content_column, line_marker_end_column)) => {
            next_content_column = line_content_column
            next_marker_end_column = line_marker_end_column
          }
          None => abort("nested blockquote depth changed after lookahead")
        }
      }
      parse_repeated_nested_block_quote_block(
        ctx, ownership, open_depth, next_content_column, next_marker_end_column,
      )
    }
    while open_depth > 1 {
      ctx.finish_node()
      open_depth -= 1
    }
  })
}

///|
fn try_parse_repeated_nested_block_quote(
  ctx : @core.ParserContext[Token, SyntaxKind],
  prefix : LinePrefix?,
  ownership : BlockQuotePrefixOwnership,
) -> Bool {
  match repeated_nested_block_quote_depth(ctx, prefix) {
    Some(depth) => {
      parse_repeated_nested_block_quote(ctx, ownership, depth, prefix)
      true
    }
    None => false
  }
}
