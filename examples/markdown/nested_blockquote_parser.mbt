// Iterative parser for physical lines containing repeated blockquote markers.
// It keeps CST stack depth proportional to syntactic quote depth while reusing
// the ordinary blockquote paragraph and Setext parsing seams.

///|
fn consume_current_block_quote_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
  owned_prefix_min_indent : Int?,
) -> (Int, Int)? {
  if prefixed_block_quote_marker(ctx, owned_prefix_min_indent) {
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
  owned_prefix_min_indent : Int?,
  count : Int,
) -> (Int, Int)? {
  let mut content_column = 0
  let mut marker_end_column = 0
  for index = 0; index < count; index = index + 1 {
    match consume_current_block_quote_marker(ctx, owned_prefix_min_indent) {
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
  owned_prefix_min_indent : Int?,
  depth : Int,
) -> (Int, Int)? {
  if ctx.peek() is Newline {
    ctx.emit_token(NewlineToken)
  }
  consume_block_quote_marker_count(ctx, owned_prefix_min_indent, depth)
}

///|
fn repeated_nested_block_quote_paragraph_starts(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  !current_line_is_link_reference_definition(ctx) &&
  !token_is_inline_end(ctx.peek(), InlineParsePolicy::paragraph())
}

///|
fn next_repeated_nested_block_quote_depth(
  ctx : @core.ParserContext[Token, SyntaxKind],
  owned_prefix_min_indent : Int?,
) -> Int {
  ctx.lookahead(() => {
    match ctx.peek() {
      Newline => ctx.emit_token(NewlineToken)
      BlankLine => ctx.emit_token(BlankLineToken)
      _ => ()
    }
    let mut depth = 0
    while consume_current_block_quote_marker(ctx, owned_prefix_min_indent)
          is Some(_) {
      depth += 1
    }
    depth
  })
}

///|
fn repeated_nested_block_quote_depth(
  ctx : @core.ParserContext[Token, SyntaxKind],
  owned_prefix_min_indent : Int?,
  prefix : LinePrefix?,
) -> Int? {
  ctx.lookahead(() => {
    match prefix {
      Some(_) => ctx.emit_token(IndentationToken)
      None => ()
    }
    let mut depth = 0
    while consume_current_block_quote_marker(ctx, owned_prefix_min_indent)
          is Some(_) {
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
  ContinueNestedMarkers(Int)
  ContinueExistingQuote(BlockContinuationAction)
}

///|
fn repeated_nested_block_quote_paragraph_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
  owned_prefix_min_indent : Int?,
  depth : Int,
) -> ContinuationDecision[RepeatedNestedBlockQuoteContinuation] {
  let nested_marker_count = ctx.lookahead(() => {
    guard ctx.peek() is Newline else { return None }
    ctx.emit_token(NewlineToken)
    let mut count = 0
    while count < depth &&
          consume_current_block_quote_marker(ctx, owned_prefix_min_indent)
          is Some(_) {
      count += 1
    }
    if count > 1 && token_continues_paragraph_after_softbreak(ctx.peek()) {
      Some(count)
    } else {
      None
    }
  })
  match nested_marker_count {
    Some(count) => Continue(ContinueNestedMarkers(count))
    None =>
      match decide_block_quote_paragraph_continuation(ctx) {
        Continue(action) => Continue(ContinueExistingQuote(action))
        Stop => Stop
      }
  }
}

///|
fn consume_repeated_nested_block_quote_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
  owned_prefix_min_indent : Int?,
  continuation : RepeatedNestedBlockQuoteContinuation,
) -> Unit {
  match continuation {
    ContinueNestedMarkers(depth) => {
      guard consume_repeated_nested_block_quote_line_prefix(
          ctx, owned_prefix_min_indent, depth,
        )
        is Some(_) else {
        abort(
          "nested blockquote continuation marker run changed after lookahead",
        )
      }
    }
    ContinueExistingQuote(action) => consume_block_continuation(ctx, action)
  }
}

///|
fn repeated_nested_block_quote_handler(
  ctx : @core.ParserContext[Token, SyntaxKind],
  owned_prefix_min_indent : Int?,
  depth : Int,
) -> ContinuationHandler[RepeatedNestedBlockQuoteContinuation] {
  {
    decide: () => {
      repeated_nested_block_quote_paragraph_continuation(
        ctx, owned_prefix_min_indent, depth,
      )
    },
    consume: continuation => {
      consume_repeated_nested_block_quote_continuation(
        ctx, owned_prefix_min_indent, continuation,
      )
    },
  }
}

///|
fn parse_repeated_nested_block_quote_paragraph(
  ctx : @core.ParserContext[Token, SyntaxKind],
  owned_prefix_min_indent : Int?,
  depth : Int,
) -> Unit {
  parse_block_quote_paragraph_with_handler(
    ctx,
    repeated_nested_block_quote_handler(ctx, owned_prefix_min_indent, depth),
  )
}

///|
fn repeated_nested_block_quote_setext_underline_depth(
  ctx : @core.ParserContext[Token, SyntaxKind],
  owned_prefix_min_indent : Int?,
  depth : Int,
) -> Int? {
  ctx.lookahead(() => {
    guard ctx.peek() is Newline else { return None }
    guard consume_repeated_nested_block_quote_line_prefix(
        ctx, owned_prefix_min_indent, depth,
      )
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
  owned_prefix_min_indent : Int?,
  depth : Int,
) -> Bool {
  ctx.lookahead(() => {
    parse_indexed_inline_container_without_continuation(
      ctx,
      InlineParsePolicy::paragraph(),
    )
    repeated_nested_block_quote_setext_underline_depth(
      ctx, owned_prefix_min_indent, depth,
    )
    is Some(_)
  })
}

///|
fn consume_repeated_nested_block_quote_setext_underline(
  ctx : @core.ParserContext[Token, SyntaxKind],
  owned_prefix_min_indent : Int?,
  depth : Int,
) -> Unit {
  guard consume_repeated_nested_block_quote_line_prefix(
      ctx, owned_prefix_min_indent, depth,
    )
    is Some(_) else {
    abort("nested blockquote setext prefix changed after lookahead")
  }
  emit_setext_underline_line(ctx)
}

///|
fn try_parse_repeated_nested_block_quote_setext_heading(
  ctx : @core.ParserContext[Token, SyntaxKind],
  owned_prefix_min_indent : Int?,
  depth : Int,
) -> Bool {
  try_parse_block_quote_setext_heading_with_handler(
    ctx,
    repeated_nested_block_quote_handler(ctx, owned_prefix_min_indent, depth),
    () => {
      repeated_nested_block_quote_setext_underline_depth(
        ctx, owned_prefix_min_indent, depth,
      )
    },
    () => {
      consume_repeated_nested_block_quote_setext_underline(
        ctx, owned_prefix_min_indent, depth,
      )
    },
  )
}

///|
fn parse_repeated_nested_block_quote_block(
  ctx : @core.ParserContext[Token, SyntaxKind],
  owned_prefix_min_indent : Int?,
  depth : Int,
  content_column : Int,
  marker_end_column : Int,
) -> Unit {
  if repeated_nested_block_quote_paragraph_starts(ctx) {
    if !repeated_nested_block_quote_starts_setext_heading(
        ctx, owned_prefix_min_indent, depth,
      ) ||
      !try_parse_repeated_nested_block_quote_setext_heading(
        ctx, owned_prefix_min_indent, depth,
      ) {
      parse_repeated_nested_block_quote_paragraph(
        ctx, owned_prefix_min_indent, depth,
      )
    }
  } else {
    parse_block_quote_after_marker(
      ctx, content_column, marker_end_column, owned_prefix_min_indent,
    )
  }
}

///|
fn parse_repeated_nested_block_quote(
  ctx : @core.ParserContext[Token, SyntaxKind],
  owned_prefix_min_indent : Int?,
  depth : Int,
  prefix : LinePrefix?,
) -> Unit {
  ctx.node(BlockQuoteNode, fn() {
    match prefix {
      Some(_) => ctx.emit_token(IndentationToken)
      None => ()
    }
    guard consume_current_block_quote_marker(ctx, owned_prefix_min_indent)
      is Some((first_content_column, first_marker_end_column)) else {
      abort("nested blockquote parser requires an opening marker")
    }
    let mut content_column = first_content_column
    let mut marker_end_column = first_marker_end_column
    for index = 1; index < depth; index = index + 1 {
      ctx.start_node(BlockQuoteNode)
      match consume_current_block_quote_marker(ctx, owned_prefix_min_indent) {
        Some((next_content_column, next_marker_end_column)) => {
          content_column = next_content_column
          marker_end_column = next_marker_end_column
        }
        None => abort("nested blockquote marker depth changed after lookahead")
      }
    }
    let mut open_depth = depth
    parse_repeated_nested_block_quote_block(
      ctx, owned_prefix_min_indent, open_depth, content_column, marker_end_column,
    )
    while true {
      let next_depth = next_repeated_nested_block_quote_depth(
        ctx, owned_prefix_min_indent,
      )
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
        match consume_current_block_quote_marker(ctx, owned_prefix_min_indent) {
          Some((line_content_column, line_marker_end_column)) => {
            next_content_column = line_content_column
            next_marker_end_column = line_marker_end_column
          }
          None => abort("nested blockquote depth changed after lookahead")
        }
      }
      parse_repeated_nested_block_quote_block(
        ctx, owned_prefix_min_indent, open_depth, next_content_column, next_marker_end_column,
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
  owned_prefix_min_indent : Int?,
) -> Bool {
  match
    repeated_nested_block_quote_depth(ctx, owned_prefix_min_indent, prefix) {
    Some(depth) => {
      parse_repeated_nested_block_quote(
        ctx, owned_prefix_min_indent, depth, prefix,
      )
      true
    }
    None => false
  }
}
