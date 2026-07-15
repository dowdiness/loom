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
priv struct LinePrefix {
  columns : Int
}

///|
fn prefixed_root_block_starts(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  match ctx.peek() {
    Indentation(_) if current_token_leading_indent(ctx) <= 3 =>
      match ctx.peek_nth(1) {
        ListMarker | OrderedListMarker(_) =>
          ctx.lookahead(() => {
            ctx.emit_token(IndentationToken)
            token_breaks_paragraph_after_newline(ctx.peek()) &&
            !setext_list_marker_line_ends_after_marker(ctx)
          })
        ThematicBreak
        | HeadingMarker(_)
        | BlockQuoteMarker
        | CodeFenceOpen(_, _)
        | HtmlBlockOpen(_) => true
        _ => false
      }
    _ => false
  }
}

///|
fn next_prefix_requires_root_block_dispatch(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  ctx.lookahead(() => {
    ctx.emit_token(NewlineToken)
    prefixed_root_block_starts(ctx)
  })
}

///|
fn parse_prefixed_block(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  let prefix = match ctx.peek() {
    Indentation(_) => LinePrefix::{ columns: current_token_leading_indent(ctx) }
    _ => abort("parse_prefixed_block requires indentation")
  }
  if prefix.columns >= 4 {
    parse_indented_code_block(ctx)
  } else {
    match ctx.peek_nth(1) {
      ThematicBreak => parse_thematic_break_with_prefix(ctx, Some(prefix))
      HeadingMarker(_) => parse_heading_with_prefix(ctx, Some(prefix))
      ListMarker => parse_list(ctx)
      OrderedListMarker(_) => parse_ordered_list(ctx)
      BlockQuoteMarker => parse_block_quote(ctx)
      CodeFenceOpen(_, _) => parse_code_block_with_prefix(ctx, Some(prefix))
      HtmlBlockOpen(_) => parse_html_block(ctx, Some(prefix))
      _ =>
        if !try_parse_setext_heading(ctx, Some(prefix)) {
          parse_paragraph_with_prefix(ctx, Some(prefix))
        }
    }
  }
}

///|

///|
/// Parse a single block. Dispatches based on the current token.
fn parse_block(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  match ctx.peek() {
    ThematicBreak => parse_thematic_break(ctx)
    HeadingMarker(_) => parse_heading(ctx)
    ListMarker if current_list_marker_indent(ctx).map_or(false, indent => {
        indent <= 3
      }) => parse_list(ctx)
    ListMarker if current_token_leading_indent(ctx) >= 4 =>
      parse_indented_code_block_from_current_line(ctx, min_indent=4)
    ListMarker => {
      ctx.emit_token(TextToken)
      parse_paragraph(ctx)
    }
    OrderedListMarker(_) if current_list_marker_indent(ctx).map_or(false, indent => {
        indent <= 3
      }) => parse_ordered_list(ctx)
    OrderedListMarker(_) if current_token_leading_indent(ctx) >= 4 =>
      parse_indented_code_block_from_current_line(ctx, min_indent=4)
    OrderedListMarker(_) => {
      ctx.emit_token(TextToken)
      parse_paragraph(ctx)
    }
    BlockQuoteMarker if current_token_leading_indent(ctx) <= 3 =>
      parse_block_quote(ctx)
    BlockQuoteMarker => {
      ctx.emit_token(TextToken)
      parse_paragraph(ctx)
    }
    CodeFenceOpen(_, _) => parse_code_block(ctx)
    HtmlBlockOpen(_) if current_token_leading_indent(ctx) <= 3 =>
      parse_html_block(ctx, None)
    HtmlBlockOpen(_) =>
      // Over-indented HTML block — treat as paragraph text.
      // Consume all remaining HtmlText lines so the lexer's HTML mode
      // doesn't leave unconsumed tokens in the stream.
      ctx.node(ParagraphNode, fn() {
        ctx.emit_token(TextToken)
        while ctx.peek() is Newline {
          ctx.emit_token(NewlineToken)
          match ctx.peek() {
            HtmlText(_) => ctx.emit_token(TextToken)
            _ => break
          }
        }
      })
    BlankLine =>
      // Consume blank lines (structural separators)
      ctx.emit_token(BlankLineToken)
    Indentation(_) => parse_prefixed_block(ctx)
    Newline =>
      // Consume stray newlines between blocks
      ctx.emit_token(NewlineToken)
    EOF => ()
    _ => if !try_parse_setext_heading(ctx, None) { parse_paragraph(ctx) }
  }
}

///|
fn try_parse_setext_heading(
  ctx : @core.ParserContext[Token, SyntaxKind],
  prefix : LinePrefix?,
) -> Bool {
  let cp = ctx.checkpoint()
  ctx.start_node(HeadingNode)
  match prefix {
    Some(_) => ctx.emit_token(IndentationToken)
    None => ()
  }
  parse_setext_heading_inline_content(ctx, allow_list_marker=true, min_indent=0)
  while ctx.peek() is Newline {
    if consume_setext_underline_after_newline(
        ctx,
        allow_list_marker=true,
        min_indent=0,
      ) {
      ctx.finish_node()
      return true
    }
    let next = ctx.peek_nth(1)
    if token_breaks_paragraph_after_newline(next) ||
      next is Newline ||
      next is EOF {
      break
    }
    ctx.emit_token(NewlineToken)
    match ctx.peek() {
      OrderedListMarker(_) => ctx.emit_token(TextToken)
      _ => ()
    }
    parse_setext_heading_inline_content(
      ctx,
      allow_list_marker=true,
      min_indent=0,
    )
  }
  ctx.finish_node()
  ctx.restore(cp)
  false
}

///|
fn consume_setext_underline_after_newline(
  ctx : @core.ParserContext[Token, SyntaxKind],
  allow_list_marker~ : Bool,
  min_indent~ : Int,
) -> Bool {
  if setext_underline_depth_after_newline(ctx, allow_list_marker~, min_indent~)
    is Some(_) {
    ctx.emit_token(NewlineToken)
    emit_setext_underline_line(ctx)
    true
  } else {
    false
  }
}

///|
fn emit_setext_underline_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  while !(ctx.peek() is Newline) &&
        !(ctx.peek() is BlankLine) &&
        ctx.peek() != EOF {
    match ctx.peek() {
      Indentation(_) => ctx.emit_token(IndentationToken)
      Text(_) | ThematicBreak | ListMarker => ctx.emit_token(HeadingMarkerToken)
      _ => ctx.bump_error()
    }
  }
}

///|
/// Parse a heading: HeadingMarker followed by inline content.
fn parse_heading_with_prefix(
  ctx : @core.ParserContext[Token, SyntaxKind],
  prefix : LinePrefix?,
) -> Unit {
  ctx.node(HeadingNode, fn() {
    match prefix {
      Some(_) => ctx.emit_token(IndentationToken)
      None => ()
    }
    ctx.emit_token(HeadingMarkerToken)
    parse_line_bound_inline_content(ctx)
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
  })
}

///|
fn parse_heading(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_heading_with_prefix(ctx, None)
}

///|
fn parse_paragraph_continuation_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  match ctx.peek() {
    Indentation(_) if ctx.peek_nth(1) is ThematicBreak => {
      ctx.emit_token(TextToken)
      ctx.emit_token(TextToken)
    }
    ListMarker => ctx.emit_token(TextToken)
    OrderedListMarker(_) => ctx.emit_token(TextToken)
    _ => ()
  }
  parse_inline_content(ctx)
}

///|
fn next_token_after_newline_is_lone_list_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  match ctx.peek_nth(1) {
    ListMarker | OrderedListMarker(_) =>
      ctx.lookahead(() => {
        ctx.emit_token(NewlineToken)
        setext_list_marker_line_ends_after_marker(ctx)
      })
    _ => false
  }
}

///|
/// Parse a paragraph: inline content possibly spanning multiple lines.
/// Continues across Newline tokens if the next token is not a block marker.
fn parse_paragraph_with_prefix(
  ctx : @core.ParserContext[Token, SyntaxKind],
  prefix : LinePrefix?,
) -> Unit {
  ctx.node(ParagraphNode, fn() {
    match prefix {
      Some(_) => ctx.emit_token(IndentationToken)
      None => ()
    }
    parse_inline_content(ctx)
    while ctx.peek() is Newline {
      let next = ctx.peek_nth(1)
      if next_prefix_requires_root_block_dispatch(ctx) ||
        (
          !next_token_after_newline_is_lone_list_marker(ctx) &&
          (
            token_breaks_paragraph_after_newline(next) ||
            next is Newline ||
            next is EOF
          )
        ) {
        ctx.emit_token(NewlineToken)
        break
      }
      ctx.emit_token(NewlineToken)
      parse_paragraph_continuation_line(ctx)
    }
  })
}

///|
fn parse_paragraph(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_paragraph_with_prefix(ctx, None)
}

///|
fn consume_block_quote_paragraph_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  match ctx.peek_nth(1) {
    BlockQuoteMarker if token_continues_paragraph_after_softbreak(
        ctx.peek_nth(2),
      ) => {
      ctx.emit_token(NewlineToken)
      ctx.emit_token(BlockQuoteMarkerToken)
      parse_paragraph_continuation_line(ctx)
      true
    }
    token if !next_unquoted_line_is_thematic_break(ctx) &&
      token_continues_paragraph_after_softbreak(token) => {
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
fn consume_quoted_setext_underline_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  ctx.emit_token(NewlineToken)
  ctx.emit_token(BlockQuoteMarkerToken)
  emit_setext_underline_line(ctx)
}

///|
fn consume_block_quote_heading_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  match ctx.peek_nth(1) {
    BlockQuoteMarker if token_continues_paragraph_after_softbreak(
        ctx.peek_nth(2),
      ) => {
      ctx.emit_token(NewlineToken)
      ctx.emit_token(BlockQuoteMarkerToken)
      parse_paragraph_continuation_line(ctx)
      true
    }
    _ => false
  }
}

///|
fn try_parse_block_quote_setext_heading(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  let cp = ctx.checkpoint()
  ctx.start_node(HeadingNode)
  parse_inline_content(ctx)
  while ctx.peek() is Newline {
    if quoted_setext_underline_depth_after_newline(ctx) is Some(_) {
      consume_quoted_setext_underline_line(ctx)
      ctx.finish_node()
      return true
    }
    if !consume_block_quote_heading_continuation(ctx) {
      break
    }
  }
  ctx.finish_node()
  ctx.restore(cp)
  false
}

///|
fn consume_quoted_blank_line_markers(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_column : Int,
  marker_end_column : Int,
) -> (Int, Int) {
  for content_column = content_column, marker_end_column = marker_end_column {
    guard ctx.peek() is BlankLine && ctx.peek_nth(1) is BlockQuoteMarker else {
      break (content_column, marker_end_column)
    }
    ctx.emit_token(BlankLineToken)
    let (next_content_column, next_marker_end_column) = current_block_quote_marker_columns(
      ctx,
    )
    ctx.emit_token(BlockQuoteMarkerToken)
    continue next_content_column, next_marker_end_column
  }
}

///|
fn consume_quoted_list_item_separator_if_matching(
  ctx : @core.ParserContext[Token, SyntaxKind],
  matches_marker : (@core.ParserContext[Token, SyntaxKind], Int, Int) -> Bool,
) -> (Int, Int)? {
  guard ctx.peek() is Newline && ctx.peek_nth(1) is BlockQuoteMarker else {
    return None
  }
  ctx.emit_token(NewlineToken)
  let (content_column, marker_end_column) = current_block_quote_marker_columns(
    ctx,
  )
  ctx.emit_token(BlockQuoteMarkerToken)
  let (content_column, marker_end_column) = consume_quoted_blank_line_markers(
    ctx, content_column, marker_end_column,
  )
  if matches_marker(ctx, content_column, marker_end_column) {
    Some((content_column, marker_end_column))
  } else {
    None
  }
}

///|
fn block_quote_list_continuation_columns(
  ctx : @core.ParserContext[Token, SyntaxKind],
  matches_marker : (@core.ParserContext[Token, SyntaxKind], Int, Int) -> Bool,
) -> (Int, Int)? {
  ctx.lookahead(() => {
    consume_quoted_list_item_separator_if_matching(ctx, matches_marker)
  })
}

///|
fn parse_block_quote_marker_scoped_list(
  ctx : @core.ParserContext[Token, SyntaxKind],
  list_kind : SyntaxKind,
  content_column : Int,
  marker_end_column : Int,
  marker_matches : (@core.ParserContext[Token, SyntaxKind], Int, Int) -> Bool,
  parse_item : (@core.ParserContext[Token, SyntaxKind]) -> Unit,
) -> Unit {
  ctx.node(list_kind, fn() {
    for content_column = content_column, marker_end_column = marker_end_column {
      guard marker_matches(ctx, content_column, marker_end_column) else {
        break
      }
      parse_item(ctx)
      match block_quote_list_continuation_columns(ctx, marker_matches) {
        Some((next_content_column, next_marker_end_column)) => {
          ignore(
            consume_quoted_list_item_separator_if_matching(ctx, marker_matches),
          )
          continue next_content_column, next_marker_end_column
        }
        None => break
      }
    }
  })
}

///|
fn current_block_quote_list_marker_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_column : Int,
  marker_end_column : Int,
) -> Int? {
  match ctx.peek() {
    ListMarker | OrderedListMarker(_) => {
      let marker_column = marker_end_column +
        leading_indent_columns_from(ctx.current_token_text(), marker_end_column)
      Some(marker_column - content_column)
    }
    Indentation(text) =>
      ctx.lookahead(() => {
        let marker_column = marker_end_column +
          leading_indent_columns_from(text, marker_end_column)
        ctx.emit_token(IndentationToken)
        match ctx.peek() {
          ListMarker | OrderedListMarker(_) =>
            Some(marker_column - content_column)
          _ => None
        }
      })
    _ => None
  }
}

///|
fn block_quote_unordered_marker_matches_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : UnorderedListMarker,
  min_indent : Int,
  content_column : Int,
  marker_end_column : Int,
) -> Bool {
  list_marker_matches(ctx, opening_marker) &&
  current_block_quote_list_marker_indent(ctx, content_column, marker_end_column).map_or(
    false,
    indent => indent >= min_indent && indent <= min_indent + 3,
  )
}

///|
fn block_quote_ordered_marker_matches_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : OrderedListMarker,
  min_indent : Int,
  content_column : Int,
  marker_end_column : Int,
) -> Bool {
  ordered_list_marker_matches(ctx, opening_marker) &&
  current_block_quote_list_marker_indent(ctx, content_column, marker_end_column).map_or(
    false,
    indent => indent >= min_indent && indent <= min_indent + 3,
  )
}

///|
fn parse_block_quote_list_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
  content_column : Int,
  marker_end_column : Int,
) -> Unit {
  match current_unordered_list_marker(ctx) {
    Some(opening_marker) =>
      parse_block_quote_marker_scoped_list(
        ctx,
        UnorderedListNode,
        content_column,
        marker_end_column,
        (ctx, content_column, marker_end_column) => {
          block_quote_unordered_marker_matches_at_min_indent(
            ctx, opening_marker, min_indent, content_column, marker_end_column,
          )
        },
        parse_list_item,
      )
    None => ()
  }
}

///|
fn parse_block_quote_list(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_column : Int,
  marker_end_column : Int,
) -> Unit {
  parse_block_quote_list_at_min_indent(
    ctx, 0, content_column, marker_end_column,
  )
}

///|
fn parse_block_quote_ordered_list_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
  content_column : Int,
  marker_end_column : Int,
) -> Unit {
  match current_ordered_list_marker(ctx) {
    Some(opening_marker) =>
      parse_block_quote_marker_scoped_list(
        ctx,
        OrderedListNode,
        content_column,
        marker_end_column,
        (ctx, content_column, marker_end_column) => {
          block_quote_ordered_marker_matches_at_min_indent(
            ctx, opening_marker, min_indent, content_column, marker_end_column,
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
  content_column : Int,
  marker_end_column : Int,
) -> Unit {
  parse_block_quote_ordered_list_at_min_indent(
    ctx, 0, content_column, marker_end_column,
  )
}

///|
fn current_block_quote_marker_columns(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> (Int, Int) {
  let marker_text = ctx.current_token_text().to_owned()
  (
    block_quote_content_column_from_marker_text(marker_text),
    count_indent_columns(marker_text, 0, marker_text.length()),
  )
}

///|
fn parse_block_quote_after_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_column : Int,
  marker_end_column : Int,
) -> Unit {
  match ctx.peek() {
    ThematicBreak => parse_thematic_break(ctx)
    HeadingMarker(_) => parse_heading(ctx)
    ListMarker if current_block_quote_list_marker_indent(
        ctx, content_column, marker_end_column,
      ).map_or(false, indent => indent <= 3) =>
      parse_block_quote_list(ctx, content_column, marker_end_column)
    ListMarker if current_block_quote_list_marker_indent(
        ctx, content_column, marker_end_column,
      ).map_or(false, indent => indent >= 4) =>
      parse_indented_code_block_from_current_line(ctx, min_indent=4)
    ListMarker => {
      ctx.emit_token(TextToken)
      parse_block_quote_paragraph(ctx)
    }
    OrderedListMarker(_) if current_block_quote_list_marker_indent(
        ctx, content_column, marker_end_column,
      ).map_or(false, indent => indent <= 3) =>
      parse_block_quote_ordered_list(ctx, content_column, marker_end_column)
    OrderedListMarker(_) if current_block_quote_list_marker_indent(
        ctx, content_column, marker_end_column,
      ).map_or(false, indent => indent >= 4) =>
      parse_indented_code_block_from_current_line(ctx, min_indent=4)
    OrderedListMarker(_) => {
      ctx.emit_token(TextToken)
      parse_block_quote_paragraph(ctx)
    }
    BlockQuoteMarker => parse_block_quote(ctx)
    CodeFenceOpen(_, _) => parse_code_block(ctx)
    Indentation(_) if ctx.peek_nth(1) is ListMarker &&
      current_block_quote_list_marker_indent(
        ctx, content_column, marker_end_column,
      ).map_or(false, indent => indent <= 3) =>
      parse_block_quote_list(ctx, content_column, marker_end_column)
    Indentation(_) if ctx.peek_nth(1) is OrderedListMarker(_) &&
      current_block_quote_list_marker_indent(
        ctx, content_column, marker_end_column,
      ).map_or(false, indent => indent <= 3) =>
      parse_block_quote_ordered_list(ctx, content_column, marker_end_column)
    Indentation(_) if current_indented_text_reaches_column(
        ctx,
        marker_end_column,
        content_column + 4,
      ) => parse_indented_code_block(ctx)
    Indentation(_) => {
      let prefix = LinePrefix::{ columns: current_token_leading_indent(ctx) }
      match ctx.peek_nth(1) {
        ThematicBreak => parse_thematic_break_with_prefix(ctx, Some(prefix))
        HeadingMarker(_) => parse_heading_with_prefix(ctx, Some(prefix))
        BlockQuoteMarker => parse_block_quote(ctx)
        CodeFenceOpen(_, _) => parse_code_block_with_prefix(ctx, Some(prefix))
        HtmlBlockOpen(_) => parse_html_block(ctx, Some(prefix))
        _ => parse_block_quote_paragraph(ctx)
      }
    }
    HtmlBlockOpen(_) => parse_html_block(ctx, None)
    Newline => ctx.emit_token(NewlineToken)
    BlankLine => ctx.emit_token(BlankLineToken)
    EOF => ()
    _ =>
      if !try_parse_block_quote_setext_heading(ctx) {
        parse_block_quote_paragraph(ctx)
      }
  }
}

///|
fn prefixed_block_quote_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  match ctx.peek() {
    Indentation(text) =>
      count_indent_columns(text, 0, text.length()) <= 3 &&
      ctx.peek_nth(1) is BlockQuoteMarker
    _ => false
  }
}

///|
fn block_quote_marker_after_newline(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  if ctx.peek_nth(1) is BlockQuoteMarker {
    true
  } else {
    match ctx.peek_nth(1) {
      Indentation(text) =>
        count_indent_columns(text, 0, text.length()) <= 3 &&
        ctx.peek_nth(2) is BlockQuoteMarker
      _ => false
    }
  }
}

///|
fn consume_block_quote_child_separator(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  if ctx.peek() is Newline && block_quote_marker_after_newline(ctx) {
    ctx.emit_token(NewlineToken)
  }
}

///|
fn parse_block_quote(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(BlockQuoteNode, fn() {
    while ctx.peek() is BlockQuoteMarker || prefixed_block_quote_marker(ctx) {
      if prefixed_block_quote_marker(ctx) {
        ctx.emit_token(IndentationToken)
      }
      let (content_column, marker_end_column) = current_block_quote_marker_columns(
        ctx,
      )
      ctx.emit_token(BlockQuoteMarkerToken)
      parse_block_quote_after_marker(ctx, content_column, marker_end_column)
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
        while list_marker_matches_at_min_indent(ctx, opening_marker, min_indent) &&
              current_list_marker_indent(ctx).map_or(false, indent => {
                indent <= min_indent + 3
              }) {
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
    indent >= content_indent && indent <= content_indent + 3
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
    Indentation(_) =>
      match ctx.peek_nth(1) {
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
    _ => false
  }
}

///|
fn next_list_marker_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Int? {
  ctx.lookahead(() => {
    ctx.emit_token(NewlineToken)
    match ctx.peek() {
      ListMarker | OrderedListMarker(_) | Indentation(_) =>
        match ctx.peek() {
          Indentation(_) =>
            match ctx.peek_nth(1) {
              ListMarker | OrderedListMarker(_) =>
                current_list_marker_indent(ctx)
              _ => None
            }
          _ => current_list_marker_indent(ctx)
        }
      _ => None
    }
  })
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
            indent >= content_indent && indent <= content_indent + 3
          }) {
          ctx.emit_token(NewlineToken)
          ignore(parse_nested_list_at_current_marker(ctx, content_indent))
        } else {
          break
        }
      ListMarker | OrderedListMarker(_) | Indentation(_) =>
        if !parse_nested_list_at_current_marker(ctx, content_indent) {
          break
        }
      _ => break
    }
  }
}

///|
fn text_leading_space_char_count(text : String) -> Int {
  text.length() - text.trim_start(chars=" ".view()).length()
}

///|
fn token_can_start_list_item_continuation_paragraph(
  token : Token,
  content_indent : Int,
) -> Bool {
  match token {
    Text(text) => text_leading_space_char_count(text) >= content_indent
    _ => !is_block_boundary(token) && content_indent <= 0
  }
}

///|
fn token_can_continue_list_item_paragraph_after_newline(
  token : Token,
  allow_ordered_marker~ : Bool,
) -> Bool {
  match token {
    Text(text) => direct_list_item_text_has_non_blank_content(text)
    _ =>
      token_can_start_lazy_list_item_continuation(token, allow_ordered_marker~)
  }
}

///|
fn try_continue_empty_list_item_after_newline(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
) -> Bool {
  guard ctx.peek() is Newline else { return false }
  let starts_continuation = token_can_start_list_item_continuation_paragraph(
      ctx.peek_nth(1),
      content_indent,
    ) ||
    next_indented_text_indent_after_newline(ctx).map_or(false, indent => {
      indent >= content_indent
    })
  let is_prefixed_thematic_break = match ctx.peek_nth(1) {
    Indentation(text) =>
      count_indent_columns(text, 0, text.length()) < content_indent + 4 &&
      ctx.peek_nth(2) is ThematicBreak
    _ => false
  }
  guard starts_continuation && !is_prefixed_thematic_break else { return false }
  ctx.emit_token(NewlineToken)
  if !try_parse_list_item_indented_flow(ctx, content_indent) {
    parse_paragraph(ctx)
  }
  true
}

///|
fn try_continue_list_item_after_blank_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
) -> Bool {
  guard ctx.peek() is BlankLine ||
    (ctx.peek() is Newline && ctx.peek_nth(1) is BlankLine) else {
    return false
  }
  let checkpoint = ctx.checkpoint()
  if ctx.peek() is Newline {
    ctx.emit_token(NewlineToken)
  }
  while ctx.peek() is BlankLine {
    ctx.emit_token(BlankLineToken)
  }
  match ctx.peek() {
    BlockQuoteMarker if current_token_text_has_min_leading_spaces(
        ctx, content_indent,
      ) => {
      parse_block_quote(ctx)
      true
    }
    Indentation(_) if prefixed_list_item_block_starts(ctx, content_indent) => {
      parse_list_item_prefixed_block(ctx)
      true
    }
    Indentation(_) => {
      let indent = current_token_leading_indent(ctx)
      if indent >= content_indent + 4 {
        parse_indented_code_block_at_min_indent(ctx, content_indent + 4)
        true
      } else if indent >= content_indent {
        parse_paragraph(ctx)
        true
      } else if token_can_start_list_item_continuation_paragraph(
          ctx.peek(),
          content_indent,
        ) {
        parse_paragraph(ctx)
        true
      } else {
        ctx.restore(checkpoint)
        false
      }
    }
    _ if token_can_start_list_item_continuation_paragraph(
        ctx.peek(),
        content_indent,
      ) => {
      parse_paragraph(ctx)
      true
    }
    _ => {
      ctx.restore(checkpoint)
      false
    }
  }
}

///|
fn try_parse_list_item_block_after_newline(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
  allow_prefixed_blocks~ : Bool,
) -> Bool {
  guard ctx.peek() is Newline else { return false }
  let checkpoint = ctx.checkpoint()
  ctx.emit_token(NewlineToken)
  match ctx.peek() {
    BlockQuoteMarker if !(ctx.peek_nth(1) is BlankLine) &&
      current_token_text_has_min_leading_spaces(ctx, content_indent) => {
      parse_block_quote(ctx)
      true
    }
    Indentation(_) if allow_prefixed_blocks &&
      prefixed_list_item_block_starts(ctx, content_indent) => {
      parse_list_item_prefixed_block(ctx)
      true
    }
    _ => {
      ctx.restore(checkpoint)
      false
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

///|
fn next_prefix_is_list_marker_boundary(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
) -> Bool {
  match ctx.peek_nth(1) {
    Indentation(text) => {
      let indent = count_indent_columns(text, 0, text.length())
      if indent >= content_indent + 4 {
        false
      } else {
        match ctx.peek_nth(2) {
          ListMarker | OrderedListMarker(_) => true
          _ => false
        }
      }
    }
    _ => false
  }
}

///|
fn prefixed_list_item_block_starts(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
) -> Bool {
  match ctx.peek() {
    Indentation(_) => {
      let indent = current_token_leading_indent(ctx)
      if indent < content_indent || indent >= content_indent + 4 {
        false
      } else {
        match ctx.peek_nth(1) {
          ThematicBreak
          | HeadingMarker(_)
          | CodeFenceOpen(_, _)
          | HtmlBlockOpen(_) => true
          BlockQuoteMarker => !(ctx.peek_nth(2) is BlankLine)
          _ => false
        }
      }
    }
    _ => false
  }
}

///|
fn next_prefix_requires_list_item_block_dispatch(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
) -> Bool {
  ctx.lookahead(() => {
    ctx.emit_token(NewlineToken)
    match ctx.peek() {
      Indentation(_) => prefixed_list_item_block_starts(ctx, content_indent)
      _ => false
    }
  })
}

///|
/// Parse list-item paragraph content, including lazy continuation lines.
fn parse_list_item_inline_content(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
  allow_ordered_marker~ : Bool,
) -> Unit {
  let has_paragraph_content = list_item_line_starts_paragraph(ctx)
  parse_inline_content_with_policy(
    ctx,
    InlineParsePolicy::list_item(allow_ordered_marker~),
  )
  while has_paragraph_content && ctx.peek() is Newline {
    let next = ctx.peek_nth(1)
    if (
        allow_ordered_marker &&
        next_ordered_marker_starts_nested_list(ctx, content_indent)
      ) ||
      next_prefix_is_list_marker_boundary(ctx, content_indent) ||
      next_prefix_requires_list_item_block_dispatch(ctx, content_indent) {
      break
    }
    if !token_can_continue_list_item_paragraph_after_newline(
        next,
        allow_ordered_marker~,
      ) {
      break
    }
    ctx.emit_token(NewlineToken)
    match ctx.peek() {
      OrderedListMarker(_) if allow_ordered_marker => ctx.emit_token(TextToken)
      _ => ()
    }
    parse_inline_content_with_policy(
      ctx,
      InlineParsePolicy::list_item(allow_ordered_marker~),
    )
  }
}

///|
fn parse_inline_thematic_break(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  ctx.node(ThematicBreakNode, fn() {
    while !(ctx.peek() is Newline) && ctx.peek() != EOF {
      match ctx.peek() {
        Text(_) => ctx.emit_token(TextToken)
        Star => ctx.emit_token(StarToken)
        StarStar => ctx.emit_token(StarStarToken)
        _ => ctx.bump_error()
      }
    }
  })
}

///|
fn try_parse_list_item_setext_heading(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
  allow_ordered_marker~ : Bool,
) -> Bool {
  let cp = ctx.checkpoint()
  ctx.start_node(HeadingNode)
  parse_list_item_setext_heading_inline_content(
    ctx,
    allow_ordered_marker~,
    min_indent=content_indent,
  )
  while ctx.peek() is Newline {
    if consume_setext_underline_after_newline(
        ctx,
        allow_list_marker=false,
        min_indent=content_indent,
      ) {
      ctx.finish_node()
      return true
    }
    let next = ctx.peek_nth(1)
    if (
        allow_ordered_marker &&
        next_ordered_marker_starts_nested_list(ctx, content_indent)
      ) ||
      next_prefix_is_list_marker_boundary(ctx, content_indent) ||
      next_prefix_requires_list_item_block_dispatch(ctx, content_indent) {
      break
    }
    if !token_can_continue_list_item_paragraph_after_newline(
        next,
        allow_ordered_marker~,
      ) {
      break
    }
    ctx.emit_token(NewlineToken)
    match ctx.peek() {
      OrderedListMarker(_) if allow_ordered_marker => ctx.emit_token(TextToken)
      _ => ()
    }
    parse_list_item_setext_heading_inline_content(
      ctx,
      allow_ordered_marker~,
      min_indent=content_indent,
    )
  }
  ctx.finish_node()
  ctx.restore(cp)
  false
}

///|
fn current_token_leading_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Int {
  count_leading_indent(ctx.current_token_text())
}

///|
fn current_list_marker_body_end_offset(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Int? {
  let marker_text = ctx.current_token_text().to_owned()
  match ctx.peek() {
    ListMarker => list_marker_body_end_offset(marker_text, ordered=false)
    OrderedListMarker(_) =>
      list_marker_body_end_offset(marker_text, ordered=true)
    _ => None
  }
}

///|
fn following_text_leading_indent(token : Token, start_col : Int) -> Int {
  match token {
    Text(text) if direct_list_item_text_has_non_blank_content(text) =>
      leading_indent_columns_from(text, start_col)
    _ => 0
  }
}

///|
fn columns_after(text : String, start_column : Int) -> Int {
  text.fold(init=start_column, (column, ch) => {
    match ch {
      ' ' => column + 1
      '\t' => next_tab_stop(column)
      _ => column + 1
    }
  })
}

///|
fn consume_list_item_prefix(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Int {
  match ctx.peek() {
    Indentation(_) => {
      let columns = current_token_leading_indent(ctx)
      ctx.emit_token(IndentationToken)
      columns
    }
    _ => 0
  }
}

///|
fn current_list_item_content_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  marker_start_column : Int,
) -> Int {
  let marker_text = ctx.current_token_text().to_owned()
  let marker_end_column = columns_after(marker_text, marker_start_column)
  guard current_list_marker_body_end_offset(ctx) is Some(body_end) else {
    return marker_end_column + 1
  }
  let body_end_column = columns_after(
    marker_text[0:body_end].to_owned(),
    marker_start_column,
  )
  let marker_padding = marker_end_column - body_end_column
  let following_padding = following_text_leading_indent(
    ctx.peek_nth(1),
    marker_end_column,
  )
  let padding = marker_padding + following_padding
  if padding == 0 {
    body_end_column + 1
  } else if padding <= 4 {
    body_end_column + padding
  } else {
    body_end_column + 1
  }
}

///|
fn current_text_reaches_indented_code_column(
  ctx : @core.ParserContext[Token, SyntaxKind],
  marker_end_column : Int,
  content_indent : Int,
) -> Bool {
  match ctx.peek() {
    Text(text) if direct_list_item_text_has_non_blank_content(text) => {
      let first_content_column = marker_end_column +
        leading_indent_columns_from(text, marker_end_column)
      first_content_column >= content_indent + 4
    }
    _ => false
  }
}

///|
fn current_indented_text_reaches_column(
  ctx : @core.ParserContext[Token, SyntaxKind],
  start_column : Int,
  target_column : Int,
) -> Bool {
  match ctx.peek() {
    Indentation(text) => {
      let first_content_column = start_column +
        leading_indent_columns_from(text, start_column)
      first_content_column >= target_column
    }
    _ => false
  }
}

///|
fn next_indented_text_indent_after_newline(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Int? {
  ctx.lookahead(() => {
    ctx.emit_token(NewlineToken)
    match ctx.peek() {
      Indentation(_) => Some(current_token_leading_indent(ctx))
      _ => None
    }
  })
}

///|
fn parse_list_item_prefixed_block(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  let prefix = match ctx.peek() {
    Indentation(_) => LinePrefix::{ columns: current_token_leading_indent(ctx) }
    _ => abort("parse_list_item_prefixed_block requires indentation")
  }
  match ctx.peek_nth(1) {
    ThematicBreak => parse_thematic_break_with_prefix(ctx, Some(prefix))
    HeadingMarker(_) => parse_heading_with_prefix(ctx, Some(prefix))
    BlockQuoteMarker => parse_block_quote(ctx)
    CodeFenceOpen(_, _) => parse_code_block_with_prefix(ctx, Some(prefix))
    HtmlBlockOpen(_) => parse_html_block(ctx, Some(prefix))
    _ => parse_paragraph_with_prefix(ctx, Some(prefix))
  }
}

///|
fn try_parse_list_item_indented_flow(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
) -> Bool {
  match ctx.peek() {
    Indentation(_) if current_token_leading_indent(ctx) >= content_indent + 4 => {
      parse_indented_code_block_at_min_indent(ctx, content_indent + 4)
      true
    }
    Indentation(_) if current_token_leading_indent(ctx) >= content_indent =>
      match ctx.peek_nth(1) {
        ListMarker | OrderedListMarker(_) =>
          parse_nested_list_at_current_marker(ctx, content_indent)
        _ => {
          parse_list_item_prefixed_block(ctx)
          true
        }
      }
    _ => false
  }
}

///|
fn emit_current_token_with_actual_kind(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(ctx.peek().to_raw())
  ctx.emit_token(kind)
}

///|
fn emit_indented_code_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  match ctx.peek() {
    Indentation(_) | Text(_) => ctx.emit_token(IndentationToken)
    _ => ()
  }
  while !(ctx.peek() is Newline) &&
        !(ctx.peek() is BlankLine) &&
        ctx.peek() != EOF {
    emit_current_token_with_actual_kind(ctx)
  }
}

///|
fn parse_indented_code_block_from_current_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent~ : Int,
) -> Unit {
  ctx.node(CodeBlockNode, fn() {
    emit_indented_code_line(ctx)
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
    while ctx.peek() != EOF {
      match ctx.peek() {
        Indentation(_) if current_token_leading_indent(ctx) >= min_indent =>
          emit_indented_code_line(ctx)
        Newline => ctx.emit_token(NewlineToken)
        BlankLine => ctx.emit_token(BlankLineToken)
        _ => break
      }
    }
  })
}

///|
fn parse_list_item_body(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
  marker_end_column : Int,
  allow_ordered_marker~ : Bool,
) -> Unit {
  let has_paragraph_content = list_item_line_starts_paragraph(ctx)
  match ctx.peek() {
    ListMarker => {
      parse_list_at_min_indent(ctx, 0)
      return
    }
    OrderedListMarker(_) => {
      parse_ordered_list_at_min_indent(ctx, 0)
      return
    }
    _ => ()
  }
  if current_text_reaches_indented_code_column(
      ctx, marker_end_column, content_indent,
    ) {
    parse_indented_code_block_from_current_line(
      ctx,
      min_indent=content_indent + 4,
    )
  } else if line_at_offset_is_thematic_break(ctx, 0) {
    parse_inline_thematic_break(ctx)
  } else if !has_paragraph_content ||
    !try_parse_list_item_setext_heading(
      ctx,
      content_indent,
      allow_ordered_marker~,
    ) {
    parse_list_item_inline_content(ctx, content_indent, allow_ordered_marker~)
  }
  if !has_paragraph_content {
    ignore(try_continue_empty_list_item_after_newline(ctx, content_indent))
  }
  while try_parse_list_item_block_after_newline(
          ctx,
          content_indent,
          allow_prefixed_blocks=has_paragraph_content,
        ) {
    ()
  }
  if has_paragraph_content {
    while try_continue_list_item_after_blank_line(ctx, content_indent) {
      ()
    }
  }
  while try_parse_list_item_indented_flow(ctx, content_indent) {
    ()
  }
  parse_nested_list_item_flow(ctx, content_indent)
}

///|
/// Parse a single list item: ListMarker followed by inline content.
fn parse_list_item(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(ListItemNode, fn() {
    let marker_start_column = consume_list_item_prefix(ctx)
    let content_indent = current_list_item_content_indent(
      ctx, marker_start_column,
    )
    let marker_end_column = columns_after(
      ctx.current_token_text().to_owned(),
      marker_start_column,
    )
    ctx.emit_token(ListMarkerToken)
    parse_list_item_body(
      ctx,
      content_indent,
      marker_end_column,
      allow_ordered_marker=true,
    )
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
              ) &&
              current_list_marker_indent(ctx).map_or(false, indent => {
                indent <= min_indent + 3
              }) {
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
    let marker_start_column = consume_list_item_prefix(ctx)
    let content_indent = current_list_item_content_indent(
      ctx, marker_start_column,
    )
    let marker_end_column = columns_after(
      ctx.current_token_text().to_owned(),
      marker_start_column,
    )
    ctx.emit_token(OrderedListMarkerToken)
    parse_list_item_body(
      ctx,
      content_indent,
      marker_end_column,
      allow_ordered_marker=false,
    )
  })
}

///|
fn parse_thematic_break_with_prefix(
  ctx : @core.ParserContext[Token, SyntaxKind],
  prefix : LinePrefix?,
) -> Unit {
  ctx.node(ThematicBreakNode, fn() {
    match prefix {
      Some(_) => ctx.emit_token(IndentationToken)
      None => ()
    }
    ctx.emit_token(ThematicBreakToken)
    if ctx.peek() is BlankLine {
      ctx.emit_token(BlankLineToken)
    }
  })
}

///|
fn parse_thematic_break(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(ThematicBreakNode, fn() {
    ctx.emit_token(ThematicBreakToken)
    if ctx.peek() is BlankLine {
      ctx.emit_token(BlankLineToken)
    }
  })
}

///|
fn html_newline_run_continues(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  for i = 1 {
    match ctx.peek_nth(i) {
      HtmlText(_) => break true
      Newline => continue i + 1
      _ => break false
    }
  }
}

///|
fn parse_html_block(
  ctx : @core.ParserContext[Token, SyntaxKind],
  prefix : LinePrefix?,
) -> Unit {
  ctx.node(HtmlBlockNode, fn() {
    match prefix {
      Some(_) => ctx.emit_token(IndentationToken)
      None => ()
    }
    ctx.emit_token(HtmlBlockOpenToken)
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
    while ctx.peek() is HtmlText(_) ||
          (ctx.peek() is Newline && html_newline_run_continues(ctx)) {
      match ctx.peek() {
        HtmlText(_) => ctx.emit_token(HtmlTextToken)
        Newline => ctx.emit_token(NewlineToken)
        _ => ()
      }
      if ctx.peek() is Newline && !(ctx.peek_nth(1) is Newline) {
        ctx.emit_token(NewlineToken)
      }
    }
    // Trailing newline run before EOF: when a delimiter-terminated block
    // (type 1/2) runs to end-of-document without finding its closing tag,
    // blank lines at the end are part of the block content, not structural
    // separators.  Consume them so html_block_value includes them.
    while ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
  })
}

///|
/// Parse a fenced code block: CodeFenceOpen, content lines, CodeFenceClose.
fn parse_code_block(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_code_block_with_prefix(ctx, None)
}

///|
fn parse_code_block_with_prefix(
  ctx : @core.ParserContext[Token, SyntaxKind],
  prefix : LinePrefix?,
) -> Unit {
  ctx.node(CodeBlockNode, fn() {
    match prefix {
      Some(_) => ctx.emit_token(IndentationToken)
      None => ()
    }
    ctx.emit_token(CodeFenceOpenToken)
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
    while !(ctx.peek() is CodeFenceClose) && ctx.peek() != EOF {
      match ctx.peek() {
        CodeText(_) => ctx.emit_token(CodeTextToken)
        Newline => ctx.emit_token(NewlineToken)
        BlankLine => ctx.emit_token(BlankLineToken)
        _ => ctx.bump_error()
      }
    }
    if ctx.peek() is CodeFenceClose {
      ctx.emit_token(CodeFenceCloseToken)
    }
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    } else if ctx.peek() is BlankLine {
      ctx.emit_token(BlankLineToken)
    }
  })
}

///|
/// Parse an indented code block: 4+ spaces of indentation per line.
/// Consumes all subsequent Indentation lines and blank lines until
/// a non-indented, non-blank line terminates the block.
fn parse_indented_code_block_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
) -> Unit {
  ctx.node(CodeBlockNode, fn() {
    while ctx.peek() != EOF {
      match ctx.peek() {
        Indentation(_) if current_token_leading_indent(ctx) >= min_indent =>
          emit_indented_code_line(ctx)
        Newline => ctx.emit_token(NewlineToken)
        BlankLine => ctx.emit_token(BlankLineToken)
        _ => break
      }
    }
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    } else if ctx.peek() is BlankLine {
      ctx.emit_token(BlankLineToken)
    }
  })
}

///|
fn parse_indented_code_block(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  parse_indented_code_block_at_min_indent(ctx, 4)
}
