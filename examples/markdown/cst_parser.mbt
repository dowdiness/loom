///|
/// Root entry point for the Markdown parser.
fn parse_root(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_markdown_document_blocks(ctx)
}

///|
/// Parse the document: a sequence of blocks until EOF.
fn parse_markdown_document_blocks(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  while ctx.peek() != EOF {
    parse_block(ctx)
  }
}

///|
priv enum LinePrefix {
  PresentLinePrefix
}

///|
/// Who owns the structural indent before a blockquote marker on continuation
/// lines. Root markers allow ≤3 columns; a list item may own a wider band.
priv enum BlockQuotePrefixOwnership {
  Root
  ListOwned(Int)
}

///|
fn BlockQuotePrefixOwnership::accepts_marker_indent(
  self : BlockQuotePrefixOwnership,
  columns : Int,
) -> Bool {
  match self {
    Root => columns <= 3
    ListOwned(min_indent) => columns >= min_indent && columns < min_indent + 4
  }
}

///|
/// Root ≤3 always; list-owned containers also accept their `[min, min+4)` band.
fn BlockQuotePrefixOwnership::accepts_container_marker_indent(
  self : BlockQuotePrefixOwnership,
  columns : Int,
) -> Bool {
  match self {
    Root => self.accepts_marker_indent(columns)
    ListOwned(_) =>
      Root.accepts_marker_indent(columns) || self.accepts_marker_indent(columns)
  }
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
        | HtmlBlockOpen(_, _) => true
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
fn block_token_fact(token : Token) -> BlockTokenFact {
  match token {
    ThematicBreak => FactThematicBreak
    HeadingMarker(_) => FactHeading
    ListMarker => FactUnorderedMarker
    OrderedListMarker(_) => FactOrderedMarker
    BlockQuoteMarker => FactBlockQuoteMarker
    CodeFenceOpen(_, _) => FactFence
    HtmlBlockOpen(_, _) => FactHtmlBlock
    BlankLine => FactBlank
    Indentation(_) => FactIndentation
    Newline => FactNewline
    EOF => FactEnd
    _ => FactInline
  }
}

///|
fn observe_root_block_start(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> BlockLineFacts {
  let current = ctx.peek()
  let current_fact = if current_line_is_link_reference_definition(ctx) {
    FactReferenceDefinition
  } else {
    block_token_fact(current)
  }
  let current_indent = match current {
    ListMarker | OrderedListMarker(_) =>
      current_list_marker_indent(ctx).map_or(-1, indent => indent)
    BlockQuoteMarker | HtmlBlockOpen(_, _) => current_token_leading_indent(ctx)
    Indentation(_) => current_token_leading_indent(ctx)
    _ => 0
  }
  let prefixed = current is Indentation(_) && current_indent < 4
  let after_prefix = if prefixed {
    block_token_fact(ctx.peek_nth(1))
  } else {
    FactInline
  }
  BlockStart(BlockStartFacts::{
    current: current_fact,
    after_prefix,
    current_indent,
    prefixed,
  })
}

///|
fn current_line_prefix(prefixed : Bool) -> LinePrefix? {
  if prefixed {
    Some(PresentLinePrefix)
  } else {
    None
  }
}

///|
fn parse_over_indented_html_paragraph(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  // Consume all remaining HtmlText lines so the lexer's HTML mode doesn't
  // leave unconsumed tokens in the stream.
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
}

///|
fn execute_root_block_start(
  ctx : @core.ParserContext[Token, SyntaxKind],
  action : BlockStartAction,
) -> Unit {
  match action {
    StartThematicBreak(prefixed) =>
      parse_thematic_break_with_prefix(ctx, current_line_prefix(prefixed))
    StartHeading(prefixed) =>
      parse_heading_with_prefix(ctx, current_line_prefix(prefixed))
    StartUnorderedList => parse_list(ctx)
    StartOrderedList => parse_ordered_list(ctx)
    StartBlockQuote => parse_block_quote(ctx)
    StartCodeFence(prefixed) =>
      parse_code_block_with_prefix(ctx, current_line_prefix(prefixed))
    StartHtmlBlock(prefixed) =>
      parse_html_block(ctx, current_line_prefix(prefixed))
    StartReferenceDefinition => parse_link_reference_definition(ctx)
    StartIndentedCode => parse_indented_code_block(ctx)
    StartIndentedMarkerCode =>
      parse_indented_code_block_from_current_line(ctx, min_indent=4)
    StartParagraph(prefixed) => {
      let prefix = current_line_prefix(prefixed)
      if !try_parse_setext_heading(ctx, prefix) {
        parse_paragraph_with_prefix(ctx, prefix)
      }
    }
    StartMarkerParagraph => {
      ctx.emit_token(TextToken)
      parse_paragraph(ctx)
    }
    StartOverIndentedHtmlParagraph => parse_over_indented_html_paragraph(ctx)
    ConsumeBlankLine => ctx.emit_token(BlankLineToken)
    ConsumeNewline => ctx.emit_token(NewlineToken)
    EndOfInput => ()
    SetextUnderline => abort("setext underline is not a root block action")
  }
}

///|

///|
/// Parse a single block. Dispatches based on the current token.
fn parse_block(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  if current_line_has_invalid_reference_definition_angle_destination(ctx) {
    parse_invalid_reference_definition_angle_destination_paragraph(ctx)
    return
  }
  let transition = decide_block_container(
    root_block_container_state(ParagraphMode, false),
    observe_root_block_start(ctx),
  )
  match transition.decision {
    StartBlock(action) => execute_root_block_start(ctx, action)
    Decline => abort("root block decision declined complete facts")
    _ => abort("root block decision returned a continuation")
  }
}

///|
fn decide_setext_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> ContinuationDecision[BlockContinuationAction] {
  let at_newline = ctx.peek() is Newline
  let setext_underline = at_newline &&
    setext_underline_depth_after_newline(
      ctx,
      allow_list_marker=true,
      min_indent=0,
    )
    is Some(_)
  let next = ctx.peek_nth(1)
  let facts = RootContinuation(RootContinuationFacts::{
    next: block_token_fact(next),
    at_newline,
    setext_underline,
    prefixed_block_start: false,
    lone_list_marker: false,
    next_breaks_paragraph: token_breaks_paragraph_after_newline(next),
    over_indented_atx: false,
    prefix: NoPrefix,
  })
  continuation_decision_from_transition(
    decide_block_container(root_block_container_state(SetextMode, true), facts),
  )
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
  let handler : ContinuationHandler[BlockContinuationAction] = {
    decide: () => decide_setext_continuation(ctx),
    consume: action => consume_block_continuation(ctx, action),
  }
  parse_indexed_inline_container(
    ctx,
    InlineParsePolicy::setext_heading(),
    handler,
  )
  if consume_setext_underline_after_newline(
      ctx,
      allow_list_marker=true,
      min_indent=0,
    ) {
    ctx.finish_node()
    true
  } else {
    ctx.finish_node()
    ctx.restore(cp)
    false
  }
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
      Text(_) | ThematicBreak | ListMarker =>
        ctx.emit_token(SetextHeadingUnderlineToken)
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
    ctx.emit_token(AtxHeadingMarkerToken)
    parse_indexed_inline_container_without_continuation(
      ctx,
      InlineParsePolicy::line_bound(),
    )
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
fn observe_continuation_prefix(
  ctx : @core.ParserContext[Token, SyntaxKind],
  offset : Int,
) -> ContinuationPrefixKind {
  let next = ctx.peek_nth(offset)
  match next {
    Indentation(_) =>
      match ctx.peek_nth(offset + 1) {
        ThematicBreak | ListMarker | OrderedListMarker(_) | HeadingMarker(_) =>
          IndentedStructuralPrefix
        _ => NoPrefix
      }
    ListMarker | OrderedListMarker(_) => ListMarkerPrefix
    HtmlBlockOpen(_, kind) if !kind.interrupts_paragraph() => InlineHtmlPrefix
    _ => NoPrefix
  }
}

///|
fn emit_paragraph_continuation_prefix(
  ctx : @core.ParserContext[Token, SyntaxKind],
  kind : ContinuationPrefixKind,
) -> Unit {
  match kind {
    IndentedStructuralPrefix => {
      ctx.emit_token(TextToken)
      ctx.emit_token(TextToken)
    }
    ListMarkerPrefix => ctx.emit_token(TextToken)
    // Non-interrupting open lines are raw inline HTML inside the paragraph,
    // not escaped text (CommonMark 148/187).
    InlineHtmlPrefix =>
      ctx.node(InlineHtmlNode, fn() { ctx.emit_token(TextToken) })
    NoPrefix => ()
  }
}

///|
fn continuation_decision_from_transition(
  transition : BlockTransition,
) -> ContinuationDecision[BlockContinuationAction] {
  match transition.decision {
    ContinueParagraph(action) => {
      guard transition.next_state.paragraph_open else {
        abort("continuation decision closed its paragraph state")
      }
      Continue(action)
    }
    StopParagraph(next) => {
      guard !transition.next_state.paragraph_open else {
        abort("stop decision retained its paragraph state")
      }
      match next {
        Some(_) | None => Stop
      }
    }
    Decline => Stop
    StartBlock(_) => abort("continuation facts produced a block-start decision")
  }
}

///|
fn consume_block_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
  action : BlockContinuationAction,
) -> Unit {
  match action {
    ContinueNoPrefix => ctx.emit_token(NewlineToken)
    ContinueIndentedStructuralPrefix => {
      ctx.emit_token(NewlineToken)
      emit_paragraph_continuation_prefix(ctx, IndentedStructuralPrefix)
    }
    ContinueListMarkerPrefix => {
      ctx.emit_token(NewlineToken)
      emit_paragraph_continuation_prefix(ctx, ListMarkerPrefix)
    }
    ContinueInlineHtmlPrefix => {
      ctx.emit_token(NewlineToken)
      emit_paragraph_continuation_prefix(ctx, InlineHtmlPrefix)
    }
    ContinueIndentationPrefix => {
      ctx.emit_token(NewlineToken)
      ctx.emit_token(IndentationToken)
      match ctx.peek() {
        ListMarker | OrderedListMarker(_) | HeadingMarker(_) =>
          ctx.emit_token(TextToken)
        _ => ()
      }
    }
    ContinueOrderedMarkerAsText => {
      ctx.emit_token(NewlineToken)
      ctx.emit_token(TextToken)
    }
    ContinueQuoteMarker(prefix) => {
      ctx.emit_token(NewlineToken)
      match ctx.peek() {
        Indentation(_) if ctx.peek_nth(1) is BlockQuoteMarker =>
          ctx.emit_token(IndentationToken)
        _ => ()
      }
      ctx.emit_token(BlockQuoteMarkerToken)
      emit_paragraph_continuation_prefix(ctx, prefix)
    }
    ContinueQuoteLazy(prefix) => {
      ctx.emit_token(NewlineToken)
      emit_paragraph_continuation_prefix(ctx, prefix)
    }
  }
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
fn next_line_is_over_indented_atx(
  ctx : @core.ParserContext[Token, SyntaxKind],
  next : Token,
) -> Bool {
  match next {
    Indentation(text) if count_leading_indent(text) >= 4 =>
      ctx.peek_nth(2) is HeadingMarker(_)
    _ => false
  }
}

///|
fn decide_root_paragraph_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> ContinuationDecision[BlockContinuationAction] {
  let at_newline = ctx.peek() is Newline
  let next = ctx.peek_nth(1)
  let facts = RootContinuation(RootContinuationFacts::{
    next: block_token_fact(next),
    at_newline,
    setext_underline: false,
    prefixed_block_start: at_newline &&
    next_prefix_requires_root_block_dispatch(ctx),
    lone_list_marker: at_newline &&
    next_token_after_newline_is_lone_list_marker(ctx),
    next_breaks_paragraph: token_breaks_paragraph_after_newline(next),
    over_indented_atx: at_newline && next_line_is_over_indented_atx(ctx, next),
    prefix: if at_newline {
      observe_continuation_prefix(ctx, 1)
    } else {
      NoPrefix
    },
  })
  continuation_decision_from_transition(
    decide_block_container(
      root_block_container_state(ParagraphMode, true),
      facts,
    ),
  )
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
    let handler : ContinuationHandler[BlockContinuationAction] = {
      decide: () => decide_root_paragraph_continuation(ctx),
      consume: action => consume_block_continuation(ctx, action),
    }
    parse_indexed_inline_container(ctx, InlineParsePolicy::paragraph(), handler)
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
  })
}

///|
fn parse_paragraph(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_paragraph_with_prefix(ctx, None)
}

///|
fn block_quote_marker_offset_after_newline(
  ctx : @core.ParserContext[Token, SyntaxKind],
  next : Token,
) -> Int? {
  match next {
    BlockQuoteMarker => Some(2)
    Indentation(text) if count_indent_columns(text, 0, text.length()) <= 3 &&
      ctx.peek_nth(2) is BlockQuoteMarker => Some(3)
    _ => None
  }
}

///|
fn block_quote_prefixed_block_start(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  match ctx.peek_nth(1) {
    Indentation(_) =>
      match ctx.peek_nth(2) {
        CodeFenceOpen(_, _) => true
        _ => false
      }
    _ => false
  }
}

///|
fn decide_block_quote_paragraph_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> ContinuationDecision[BlockContinuationAction] {
  let at_newline = ctx.peek() is Newline
  let next = ctx.peek_nth(1)
  let marker_offset = if at_newline {
    block_quote_marker_offset_after_newline(ctx, next)
  } else {
    None
  }
  let marked_line_continues = match marker_offset {
    Some(offset) =>
      token_continues_paragraph_after_softbreak(ctx.peek_nth(offset))
    None => false
  }
  let facts = BlockQuoteContinuation(BlockQuoteContinuationFacts::{
    at_newline,
    setext_underline: false,
    marked_line_continues,
    marked_prefix: match marker_offset {
      Some(offset) => observe_continuation_prefix(ctx, offset)
      None => NoPrefix
    },
    unquoted_line_continues: at_newline &&
    marker_offset is None &&
    !block_quote_prefixed_block_start(ctx) &&
    token_continues_paragraph_after_softbreak(next),
    unquoted_prefix: if at_newline {
      observe_continuation_prefix(ctx, 1)
    } else {
      NoPrefix
    },
    unquoted_thematic_break: at_newline &&
    marker_offset is None &&
    next_unquoted_line_is_thematic_break(ctx),
  })
  continuation_decision_from_transition(
    decide_block_container(block_quote_container_state(ParagraphMode), facts),
  )
}

///|
fn parse_block_quote_paragraph(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  let handler : ContinuationHandler[BlockContinuationAction] = {
    decide: () => decide_block_quote_paragraph_continuation(ctx),
    consume: action => consume_block_continuation(ctx, action),
  }
  parse_block_quote_paragraph_with_handler(ctx, handler)
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
fn decide_block_quote_heading_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> ContinuationDecision[BlockContinuationAction] {
  let at_newline = ctx.peek() is Newline
  let next = ctx.peek_nth(1)
  let marker_offset = if at_newline {
    block_quote_marker_offset_after_newline(ctx, next)
  } else {
    None
  }
  let marked_line_continues = match marker_offset {
    Some(offset) =>
      token_continues_paragraph_after_softbreak(ctx.peek_nth(offset))
    None => false
  }
  let facts = BlockQuoteContinuation(BlockQuoteContinuationFacts::{
    at_newline,
    setext_underline: at_newline &&
    quoted_setext_underline_depth_after_newline(ctx) is Some(_),
    marked_line_continues,
    marked_prefix: match marker_offset {
      Some(offset) => observe_continuation_prefix(ctx, offset)
      None => NoPrefix
    },
    unquoted_line_continues: false,
    unquoted_prefix: NoPrefix,
    unquoted_thematic_break: false,
  })
  continuation_decision_from_transition(
    decide_block_container(block_quote_container_state(SetextMode), facts),
  )
}

///|
fn try_parse_block_quote_setext_heading(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  let handler : ContinuationHandler[BlockContinuationAction] = {
    decide: () => decide_block_quote_heading_continuation(ctx),
    consume: action => consume_block_continuation(ctx, action),
  }
  try_parse_block_quote_setext_heading_with_handler(
    ctx,
    handler,
    () => quoted_setext_underline_depth_after_newline(ctx),
    () => consume_quoted_setext_underline_line(ctx),
  )
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
  ownership : BlockQuotePrefixOwnership,
) -> Unit {
  match ctx.peek() {
    _ if current_line_is_link_reference_definition(ctx) =>
      parse_link_reference_definition(ctx)
    ThematicBreak => parse_thematic_break(ctx)
    HeadingMarker(_) => parse_heading(ctx)
    ListMarker if current_block_quote_list_marker_indent(
        ctx, content_column, marker_end_column,
      ).map_or(false, indent => indent <= 3) =>
      parse_block_quote_list(ctx, content_column, marker_end_column)
    ListMarker if current_block_quote_list_marker_indent(
        ctx, content_column, marker_end_column,
      ).map_or(false, indent => indent >= 4) =>
      parse_quoted_indented_code_block_from_current_line(
        ctx,
        min_indent=4,
        ownership~,
      )
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
      parse_quoted_indented_code_block_from_current_line(
        ctx,
        min_indent=4,
        ownership~,
      )
    OrderedListMarker(_) => {
      ctx.emit_token(TextToken)
      parse_block_quote_paragraph(ctx)
    }
    BlockQuoteMarker => parse_block_quote_with_prefix(ctx, None, ownership)
    CodeFenceOpen(_, _) => parse_quoted_code_block_with_prefix(ctx, None)
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
      ) => parse_quoted_indented_code_block(ctx, ownership~)
    Indentation(_) => {
      let prefix = PresentLinePrefix
      match ctx.peek_nth(1) {
        ThematicBreak => parse_thematic_break_with_prefix(ctx, Some(prefix))
        HeadingMarker(_) => parse_heading_with_prefix(ctx, Some(prefix))
        BlockQuoteMarker => parse_block_quote_with_prefix(ctx, None, ownership)
        CodeFenceOpen(_, _) =>
          parse_quoted_code_block_with_prefix(ctx, Some(prefix))
        HtmlBlockOpen(_, _) => parse_html_block(ctx, Some(prefix))
        _ => parse_block_quote_paragraph(ctx)
      }
    }
    HtmlBlockOpen(_, _) => parse_html_block(ctx, None)
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
fn peek_nth_is_indented_blockquote_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
  offset : Int,
  ownership : BlockQuotePrefixOwnership,
) -> Bool {
  match ctx.peek_nth(offset) {
    Indentation(text) => {
      let columns = count_indent_columns(text, 0, text.length())
      ownership.accepts_container_marker_indent(columns) &&
      ctx.peek_nth(offset + 1) is BlockQuoteMarker
    }
    _ => false
  }
}

///|
fn peek_nth_is_blockquote_marker_start(
  ctx : @core.ParserContext[Token, SyntaxKind],
  offset : Int,
  ownership : BlockQuotePrefixOwnership,
) -> Bool {
  ctx.peek_nth(offset) is BlockQuoteMarker ||
  peek_nth_is_indented_blockquote_marker(ctx, offset, ownership)
}

///|
fn prefixed_block_quote_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
) -> Bool {
  peek_nth_is_indented_blockquote_marker(ctx, 0, ownership)
}

///|
fn block_quote_marker_after_newline(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
) -> Bool {
  peek_nth_is_blockquote_marker_start(ctx, 1, ownership)
}

///|
fn consume_block_quote_child_separator(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
) -> Unit {
  if ctx.peek() is Newline && block_quote_marker_after_newline(ctx, ownership) {
    ctx.emit_token(NewlineToken)
  }
}

///|
fn parse_block_quote_with_prefix(
  ctx : @core.ParserContext[Token, SyntaxKind],
  prefix : LinePrefix?,
  ownership : BlockQuotePrefixOwnership,
) -> Unit {
  // A list item owns its content indentation, so carry it as the min indent
  // of the owned prefix accepted on subsequent physical lines of the quote.
  if try_parse_repeated_nested_block_quote(ctx, prefix, ownership) {
    return
  }
  ctx.node(BlockQuoteNode, fn() {
    // A list item owns its content indentation, which can exceed the root
    // blockquote limit of three columns. Consume that structural prefix inside
    // the quote before entering the marker loop; otherwise this parser returns
    // successfully without advancing and its caller repeats forever.
    match prefix {
      Some(_) => ctx.emit_token(IndentationToken)
      None => ()
    }
    while ctx.peek() is BlockQuoteMarker ||
          prefixed_block_quote_marker(ctx, ownership) {
      if prefixed_block_quote_marker(ctx, ownership) {
        ctx.emit_token(IndentationToken)
      }
      let (content_column, marker_end_column) = current_block_quote_marker_columns(
        ctx,
      )
      ctx.emit_token(BlockQuoteMarkerToken)
      parse_block_quote_after_marker(
        ctx, content_column, marker_end_column, ownership,
      )
      consume_block_quote_child_separator(ctx, ownership)
    }
  })
}

///|
fn parse_block_quote(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_block_quote_with_prefix(ctx, None, Root)
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
/// Same-line nested markers have no Indentation token. Carry the parent
/// content column into the first nested item so later continuation checks use
/// the nested marker's actual source column.
priv enum ListKind {
  Unordered(UnorderedListMarker)
  Ordered(OrderedListMarker)
}

///|
fn list_kind_matches_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  kind : ListKind,
  min_indent : Int,
) -> Bool {
  match kind {
    Unordered(opening_marker) =>
      list_marker_matches_at_min_indent(ctx, opening_marker, min_indent)
    Ordered(opening_marker) =>
      ordered_list_marker_matches_at_min_indent(ctx, opening_marker, min_indent)
  }
}

///|
fn consume_list_item_separator_for_kind(
  ctx : @core.ParserContext[Token, SyntaxKind],
  kind : ListKind,
  min_indent : Int,
) -> Unit {
  match kind {
    Unordered(opening_marker) =>
      consume_list_item_separator_at_min_indent(ctx, opening_marker, min_indent)
    Ordered(opening_marker) =>
      consume_ordered_list_item_separator_at_min_indent(
        ctx, opening_marker, min_indent,
      )
  }
}

///|
fn parse_list_item_for_kind(
  ctx : @core.ParserContext[Token, SyntaxKind],
  kind : ListKind,
  first_item_marker_start_column : Int?,
) -> Unit {
  match kind {
    Unordered(_) =>
      parse_list_item_with_marker_start_column(
        ctx, first_item_marker_start_column,
      )
    Ordered(_) =>
      parse_ordered_list_item_with_marker_start_column(
        ctx, first_item_marker_start_column,
      )
  }
}

///|
fn parse_list_items_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  kind : ListKind,
  min_indent : Int,
  first_item_marker_start_column : Int?,
) -> Unit {
  let continuation_min_indent = match first_item_marker_start_column {
    Some(column) => column
    None => min_indent
  }
  if list_kind_matches_at_min_indent(ctx, kind, min_indent) &&
    current_list_marker_indent(ctx).map_or(false, indent => {
      indent <= min_indent + 3
    }) {
    parse_list_item_for_kind(ctx, kind, first_item_marker_start_column)
    consume_list_item_separator_for_kind(ctx, kind, continuation_min_indent)
    while list_kind_matches_at_min_indent(ctx, kind, continuation_min_indent) &&
          current_list_marker_indent(ctx).map_or(false, indent => {
            indent <= continuation_min_indent + 3
          }) {
      parse_list_item_for_kind(ctx, kind, None)
      consume_list_item_separator_for_kind(ctx, kind, continuation_min_indent)
    }
  }
}

///|
fn parse_list_at_min_indent_with_first_item_column(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
  first_item_marker_start_column : Int?,
) -> Unit {
  ctx.node(UnorderedListNode, fn() {
    match current_unordered_list_marker(ctx) {
      Some(opening_marker) =>
        parse_list_items_at_min_indent(
          ctx,
          Unordered(opening_marker),
          min_indent,
          first_item_marker_start_column,
        )
      None => ()
    }
  })
}

///|
fn parse_list_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
) -> Unit {
  parse_list_at_min_indent_with_first_item_column(ctx, min_indent, None)
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
) -> Bool {
  let mut consumed = false
  while true {
    match ctx.peek() {
      Newline =>
        if next_list_marker_indent(ctx).map_or(false, indent => {
            indent >= content_indent && indent <= content_indent + 3
          }) {
          ctx.emit_token(NewlineToken)
          if parse_nested_list_at_current_marker(ctx, content_indent) {
            consumed = true
          }
        } else {
          break
        }
      ListMarker | OrderedListMarker(_) | Indentation(_) =>
        if parse_nested_list_at_current_marker(ctx, content_indent) {
          consumed = true
        } else {
          break
        }
      _ => break
    }
  }
  consumed
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
/// Immutable facts shared by list-item continuation decisions. ParserContext
/// effects remain in the functions below; this keeps their call sites small
/// without exposing a new public parser API.
priv struct ListItemFlowContext {
  content_indent : Int
  marker_end_column : Int
  allow_ordered_marker : Bool
}

///|
fn try_continue_empty_list_item_after_newline(
  ctx : @core.ParserContext[Token, SyntaxKind],
  context : ListItemFlowContext,
) -> Bool {
  guard ctx.peek() is Newline else { return false }
  let starts_continuation = token_can_start_list_item_continuation_paragraph(
      ctx.peek_nth(1),
      context.content_indent,
    ) ||
    next_indented_text_indent_after_newline(ctx).map_or(false, indent => {
      indent >= context.content_indent
    })
  let is_prefixed_thematic_break = match ctx.peek_nth(1) {
    Indentation(text) =>
      count_indent_columns(text, 0, text.length()) < context.content_indent + 4 &&
      ctx.peek_nth(2) is ThematicBreak
    _ => false
  }
  guard starts_continuation && !is_prefixed_thematic_break else { return false }
  ctx.emit_token(NewlineToken)
  if current_line_is_link_reference_definition(ctx) {
    parse_link_reference_definition(ctx)
  } else if !try_parse_list_item_indented_flow_at(
      ctx,
      context,
      context.content_indent + 4,
    ) {
    parse_list_item_prefixed_paragraph(
      ctx,
      context.content_indent,
      allow_ordered_marker=context.allow_ordered_marker,
    )
  }
  true
}

///|
fn try_continue_list_item_after_blank_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
  context : ListItemFlowContext,
  allow_paragraph_continuation~ : Bool,
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
        ctx,
        context.content_indent,
      ) => {
      parse_block_quote_with_prefix(
        ctx,
        None,
        ListOwned(context.content_indent),
      )
      true
    }
    Indentation(_) if prefixed_list_item_block_starts(
        ctx,
        context.content_indent,
      ) => {
      parse_list_item_prefixed_block(ctx, context.content_indent)
      true
    }
    Indentation(_) => {
      let indent = current_token_leading_indent(ctx)
      if indent >= context.marker_end_column + 4 {
        parse_indented_code_block_at_min_indent(
          ctx,
          context.marker_end_column + 4,
        )
        true
      } else if indent >= context.content_indent &&
        prefixed_list_item_block_starts(ctx, context.content_indent) {
        parse_list_item_prefixed_block(ctx, context.content_indent)
        true
      } else if indent >= context.content_indent &&
        (
          ctx.peek_nth(1) is ListMarker ||
          ctx.peek_nth(1) is OrderedListMarker(_)
        ) {
        match parse_nested_list_at_current_marker(ctx, context.content_indent) {
          true => true
          false => {
            ctx.restore(checkpoint)
            false
          }
        }
      } else if indent >= context.content_indent &&
        ctx.peek_nth(1) is BlockQuoteMarker &&
        ctx.peek_nth(2) is BlankLine {
        ctx.restore(checkpoint)
        false
      } else if allow_paragraph_continuation && indent >= context.content_indent {
        parse_list_item_prefixed_paragraph(
          ctx,
          context.content_indent,
          allow_ordered_marker=context.allow_ordered_marker,
        )
        true
      } else if allow_paragraph_continuation &&
        token_can_start_list_item_continuation_paragraph(
          ctx.peek(),
          context.content_indent,
        ) {
        parse_list_item_prefixed_paragraph(
          ctx,
          context.content_indent,
          allow_ordered_marker=context.allow_ordered_marker,
        )
        true
      } else {
        ctx.restore(checkpoint)
        false
      }
    }
    _ if allow_paragraph_continuation &&
      token_can_start_list_item_continuation_paragraph(
        ctx.peek(),
        context.content_indent,
      ) => {
      parse_list_item_prefixed_paragraph(
        ctx,
        context.content_indent,
        allow_ordered_marker=context.allow_ordered_marker,
      )
      true
    }
    _ => {
      ctx.restore(checkpoint)
      false
    }
  }
}

///|
fn try_parse_list_item_quoted_blank_line_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
  context : ListItemFlowContext,
) -> Bool {
  guard ctx.peek() is Newline && ctx.peek_nth(1) is BlockQuoteMarker else {
    return false
  }
  let checkpoint = ctx.checkpoint()
  ctx.emit_token(NewlineToken)
  let mut saw_blank_line = false
  let mut marker_count = 0
  while ctx.peek() is BlockQuoteMarker {
    ctx.emit_token(BlockQuoteMarkerToken)
    marker_count = marker_count + 1
    if ctx.peek() is BlankLine {
      saw_blank_line = true
      while ctx.peek() is BlankLine {
        ctx.emit_token(BlankLineToken)
      }
      break
    }
  }
  guard saw_blank_line && marker_count >= 2 && ctx.peek() is BlockQuoteMarker else {
    ctx.restore(checkpoint)
    return false
  }
  while ctx.peek() is BlockQuoteMarker {
    ctx.emit_token(BlockQuoteMarkerToken)
  }
  ctx.node(ParagraphNode, fn() {
    parse_list_item_inline_content(
      ctx,
      context.content_indent,
      allow_ordered_marker=context.allow_ordered_marker,
    )
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
  })
  true
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
    _ if !allow_prefixed_blocks &&
      current_line_is_link_reference_definition(ctx) &&
      current_token_text_has_min_leading_spaces(ctx, content_indent) => {
      parse_link_reference_definition(ctx)
      true
    }
    BlockQuoteMarker if !(ctx.peek_nth(1) is BlankLine) &&
      current_token_text_has_min_leading_spaces(ctx, content_indent) => {
      parse_block_quote_with_prefix(ctx, None, ListOwned(content_indent))
      true
    }
    Indentation(_) if allow_prefixed_blocks &&
      !current_line_is_link_reference_definition(ctx) &&
      prefixed_list_item_block_starts(ctx, content_indent) => {
      parse_list_item_prefixed_block(ctx, content_indent)
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
fn next_prefix_is_list_marker_boundary(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
) -> Bool {
  match ctx.peek_nth(1) {
    Indentation(text) => {
      let indent = count_indent_columns(text, 0, text.length())
      if indent >= content_indent + 4 || (indent > 3 && indent < content_indent) {
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
      } else if current_line_is_link_reference_definition(ctx) {
        true
      } else {
        match ctx.peek_nth(1) {
          ThematicBreak
          | HeadingMarker(_)
          | CodeFenceOpen(_, _)
          | HtmlBlockOpen(_, _) => true
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
      Indentation(_) if current_line_is_link_reference_definition(ctx) => false
      Indentation(_) => prefixed_list_item_block_starts(ctx, content_indent)
      _ => false
    }
  })
}

///|
fn decide_list_item_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
  allow_ordered_marker~ : Bool,
  has_paragraph_content~ : Bool,
) -> ContinuationDecision[BlockContinuationAction] {
  let at_newline = ctx.peek() is Newline
  let observe_next_line = at_newline && has_paragraph_content
  let next = ctx.peek_nth(1)
  let facts = ListItemContinuation(ListItemContinuationFacts::{
    next: block_token_fact(next),
    next_indent: if observe_next_line {
      next_list_marker_indent(ctx)
    } else {
      None
    },
    at_newline,
    setext_underline: false,
    prefix_is_marker_boundary: observe_next_line &&
    next_prefix_is_list_marker_boundary(ctx, content_indent),
    prefixed_block_start: observe_next_line &&
    next_prefix_requires_list_item_block_dispatch(ctx, content_indent),
    next_can_continue: observe_next_line &&
    token_can_continue_list_item_paragraph_after_newline(
      next,
      allow_ordered_marker~,
    ),
  })
  continuation_decision_from_transition(
    decide_block_container(
      list_item_block_container_state(
        ParagraphMode,
        content_indent~,
        allow_ordered_marker~,
        paragraph_open=has_paragraph_content,
      ),
      facts,
    ),
  )
}

///|
fn gfm_task_marker_value(text : String) -> Bool {
  text == " " || text == "\t" || text == "x" || text == "X"
}

///|
fn gfm_task_has_following_content(
  ctx : @core.ParserContext[Token, SyntaxKind],
  follow_index : Int,
) -> Bool {
  let first_is_whitespace = match ctx.peek_nth(follow_index) {
    Text(text) => text.has_prefix(" ") || text.has_prefix("\t")
    Newline => true
    _ => false
  }
  guard first_is_whitespace else { return false }
  for index = follow_index {
    match ctx.peek_nth(index) {
      Text(text) if direct_list_item_text_has_non_blank_content(text) =>
        break true
      Text(_) | Indentation(_) | Newline => continue index + 1
      _ => break false
    }
  }
}

///|
fn try_parse_gfm_task_list_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  let marker_index = match ctx.peek() {
    LeftBracket => Some(0)
    Text(prefix) if prefix.trim(chars=" ".view()).length() == 0 &&
      ctx.peek_nth(1) is LeftBracket => Some(1)
    _ => None
  }
  guard marker_index is Some(marker_index) &&
    ctx.peek_nth(marker_index + 1) is Text(marker) &&
    gfm_task_marker_value(marker) &&
    ctx.peek_nth(marker_index + 2) is RightBracket &&
    gfm_task_has_following_content(ctx, marker_index + 3) else {
    return false
  }
  ctx.node(TaskListMarkerNode, fn() {
    if marker_index == 1 {
      ctx.emit_token(TextToken)
    }
    ctx.emit_token(LeftBracketToken)
    ctx.emit_token(TextToken)
    ctx.emit_token(RightBracketToken)
  })
  true
}

///|
/// Parse list-item paragraph content, including lazy continuation lines.
fn parse_list_item_inline_content(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
  allow_ordered_marker~ : Bool,
) -> Unit {
  let has_paragraph_content = list_item_line_starts_paragraph(ctx)
  ignore(try_parse_gfm_task_list_marker(ctx))
  let handler : ContinuationHandler[BlockContinuationAction] = {
    decide: () => {
      decide_list_item_continuation(
        ctx,
        content_indent,
        allow_ordered_marker~,
        has_paragraph_content~,
      )
    },
    consume: action => consume_block_continuation(ctx, action),
  }
  parse_indexed_inline_container(
    ctx,
    InlineParsePolicy::list_item(allow_ordered_marker~),
    handler,
  )
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
fn decide_list_item_setext_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
  allow_ordered_marker~ : Bool,
) -> ContinuationDecision[BlockContinuationAction] {
  let at_newline = ctx.peek() is Newline
  let setext_underline = at_newline &&
    setext_underline_depth_after_newline(
      ctx,
      allow_list_marker=false,
      min_indent=content_indent,
    )
    is Some(_)
  let next = ctx.peek_nth(1)
  let facts = ListItemContinuation(ListItemContinuationFacts::{
    next: block_token_fact(next),
    next_indent: if at_newline {
      next_list_marker_indent(ctx)
    } else {
      None
    },
    at_newline,
    setext_underline,
    prefix_is_marker_boundary: at_newline &&
    next_prefix_is_list_marker_boundary(ctx, content_indent),
    prefixed_block_start: at_newline &&
    next_prefix_requires_list_item_block_dispatch(ctx, content_indent),
    next_can_continue: at_newline &&
    token_can_continue_list_item_paragraph_after_newline(
      next,
      allow_ordered_marker~,
    ),
  })
  continuation_decision_from_transition(
    decide_block_container(
      list_item_block_container_state(
        SetextMode,
        content_indent~,
        allow_ordered_marker~,
        paragraph_open=true,
      ),
      facts,
    ),
  )
}

///|
fn try_parse_list_item_setext_heading(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
  allow_ordered_marker~ : Bool,
) -> Bool {
  let cp = ctx.checkpoint()
  ctx.start_node(HeadingNode)
  let handler : ContinuationHandler[BlockContinuationAction] = {
    decide: () => {
      decide_list_item_setext_continuation(
        ctx,
        content_indent,
        allow_ordered_marker~,
      )
    },
    consume: action => consume_block_continuation(ctx, action),
  }
  parse_indexed_inline_container(
    ctx,
    InlineParsePolicy::list_item_setext_heading(allow_ordered_marker~),
    handler,
  )
  if consume_setext_underline_after_newline(
      ctx,
      allow_list_marker=false,
      min_indent=content_indent,
    ) {
    ctx.finish_node()
    true
  } else {
    ctx.finish_node()
    ctx.restore(cp)
    false
  }
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
  content_indent : Int,
) -> Unit {
  if current_line_is_link_reference_definition(ctx) {
    parse_link_reference_definition(ctx)
    return
  }
  let prefix = match ctx.peek() {
    Indentation(_) => PresentLinePrefix
    _ => abort("parse_list_item_prefixed_block requires indentation")
  }
  match ctx.peek_nth(1) {
    ThematicBreak => parse_thematic_break_with_prefix(ctx, Some(prefix))
    HeadingMarker(_) => parse_heading_with_prefix(ctx, Some(prefix))
    BlockQuoteMarker =>
      parse_block_quote_with_prefix(
        ctx,
        Some(prefix),
        ListOwned(content_indent),
      )
    CodeFenceOpen(_, _) => parse_code_block_with_prefix(ctx, Some(prefix))
    HtmlBlockOpen(_, _) => parse_html_block(ctx, Some(prefix))
    _ => parse_paragraph_with_prefix(ctx, Some(prefix))
  }
}

///|
fn parse_list_item_prefixed_paragraph(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
  allow_ordered_marker~ : Bool,
) -> Unit {
  ctx.node(ParagraphNode, fn() {
    ctx.emit_token(IndentationToken)
    parse_list_item_inline_content(ctx, content_indent, allow_ordered_marker~)
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
  })
}

///|
fn try_parse_list_item_indented_flow_at(
  ctx : @core.ParserContext[Token, SyntaxKind],
  context : ListItemFlowContext,
  code_indent : Int,
) -> Bool {
  let current = ctx.peek()
  let indent = match current {
    Indentation(_) => Some(current_token_leading_indent(ctx))
    _ => None
  }
  // Preserve the old shell's lazy lookahead: code and stop branches never
  // needed the next token, while prefixed flow does.
  let prefixed_block_start = match indent {
    Some(indent) if indent >= context.content_indent && indent < code_indent =>
      prefixed_list_item_block_starts(ctx, context.content_indent)
    _ => false
  }
  let next = match indent {
    Some(indent) if indent >= context.content_indent && indent < code_indent =>
      ctx.peek_nth(1)
    _ => EOF
  }
  match
    decide_list_item_indented_flow(
      current, next, indent, context, code_indent, prefixed_block_start,
    ) {
    Stop => false
    IndentedCode => {
      parse_indented_code_block_at_min_indent(ctx, code_indent)
      true
    }
    NestedList =>
      parse_nested_list_at_current_marker(ctx, context.content_indent)
    PrefixedBlock => {
      parse_list_item_prefixed_block(ctx, context.content_indent)
      true
    }
    PrefixedParagraph => {
      parse_list_item_prefixed_paragraph(
        ctx,
        context.content_indent,
        allow_ordered_marker=context.allow_ordered_marker,
      )
      true
    }
  }
}

///|
fn try_parse_list_item_indented_flow(
  ctx : @core.ParserContext[Token, SyntaxKind],
  context : ListItemFlowContext,
) -> Bool {
  try_parse_list_item_indented_flow_at(
    ctx,
    context,
    context.marker_end_column + 4,
  )
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
fn token_is_indented_code_leftover(token : Token) -> Bool {
  match token {
    HtmlBlockOpen(_, _)
    | HtmlText(_)
    | CodeFenceOpen(_, _)
    | CodeText(_)
    | CodeFenceClose => true
    _ => false
  }
}

///|
fn leftover_token_payload_indent(token : Token) -> Int? {
  match token {
    HtmlBlockOpen(text, _) | HtmlText(text) | CodeText(text) =>
      Some(count_leading_indent(text))
    _ => None
  }
}

///|
/// HTML and fence openers may already have switched the lexer mode after a
/// four-space indent. Keep leftover same-line tokens inside the opener, but
/// only continue onto later lines that still meet the indent requirement.
fn indented_code_body_continues(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
) -> Bool {
  match ctx.peek() {
    Indentation(_) => current_token_leading_indent(ctx) >= min_indent
    Newline | BlankLine => true
    token if token_is_indented_code_leftover(token) =>
      current_token_leading_indent(ctx) >= min_indent
    _ => false
  }
}

///|
fn consume_indented_code_body_while(
  ctx : @core.ParserContext[Token, SyntaxKind],
  continues : (@core.ParserContext[Token, SyntaxKind]) -> Bool,
) -> Unit {
  while continues(ctx) {
    match ctx.peek() {
      Newline => ctx.emit_token(NewlineToken)
      BlankLine => ctx.emit_token(BlankLineToken)
      _ => emit_indented_code_line(ctx)
    }
  }
}

///|
fn consume_indented_code_body(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
) -> Unit {
  consume_indented_code_body_while(ctx, ctx => {
    indented_code_body_continues(ctx, min_indent)
  })
}

///|
/// After a newline inside quote-owned indented code, continue only when the
/// next physical line still opens with a blockquote marker and then meets the
/// indented-code indent. Bare indent leaves the quote (CommonMark 236);
/// unmarked blanks end it (242 / 252).
fn next_line_continues_quoted_indented_code(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
  ownership : BlockQuotePrefixOwnership,
) -> Bool {
  let marker_offset = match ctx.peek() {
    BlockQuoteMarker => Some(0)
    Indentation(_) if peek_nth_is_indented_blockquote_marker(ctx, 0, ownership) =>
      Some(1)
    _ => None
  }
  match marker_offset {
    None => false
    Some(offset) =>
      match ctx.peek_nth(offset + 1) {
        Indentation(text) =>
          count_indent_columns(text, 0, text.length()) >= min_indent
        token if token_is_indented_code_leftover(token) =>
          match leftover_token_payload_indent(token) {
            Some(columns) => columns >= min_indent
            None => false
          }
        _ => false
      }
  }
}

///|
fn consume_blockquote_prefix_for_quoted_indented_code(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership : BlockQuotePrefixOwnership,
) -> Unit {
  if prefixed_block_quote_marker(ctx, ownership) {
    ctx.emit_token(IndentationToken)
  }
  ctx.emit_token(BlockQuoteMarkerToken)
}

///|
/// Consume one physical line of quote-owned indented code. Returns `true` when
/// a trailing newline was taken so the caller may try a marked continuation.
fn try_consume_quoted_indented_code_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
) -> Bool {
  while indented_code_body_continues(ctx, min_indent) {
    match ctx.peek() {
      Newline => {
        ctx.emit_token(NewlineToken)
        return true
      }
      BlankLine => return false
      _ => emit_indented_code_line(ctx)
    }
  }
  false
}

///|
/// Consume quote-owned indented code for the current line and any further
/// marked indented-code lines. Unmarked line breaks leave the quote.
fn consume_quoted_indented_code_body(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
  ownership : BlockQuotePrefixOwnership,
) -> Unit {
  while try_consume_quoted_indented_code_line(ctx, min_indent) {
    guard next_line_continues_quoted_indented_code(ctx, min_indent, ownership) else {
      break
    }
    consume_blockquote_prefix_for_quoted_indented_code(ctx, ownership)
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
    consume_indented_code_body(ctx, min_indent)
  })
}

///|
/// Emit the current quote-owned indented-code line, then absorb further marked
/// indented-code lines into the same block.
fn parse_quoted_indented_code_block_from_current_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent~ : Int,
  ownership~ : BlockQuotePrefixOwnership,
) -> Unit {
  ctx.node(CodeBlockNode, fn() {
    emit_indented_code_line(ctx)
    consume_quoted_indented_code_body(ctx, min_indent, ownership)
  })
}

///|
/// Parse continuation blocks after the inline body. The order is the
/// container grammar: newline-prefixed blocks, indented flow, blank-line
/// continuation, another indented flow, then nested lists.
fn parse_list_item_flow_after_body(
  ctx : @core.ParserContext[Token, SyntaxKind],
  context : ListItemFlowContext,
  has_paragraph_content : Bool,
) -> Unit {
  while try_parse_list_item_block_after_newline(
          ctx,
          context.content_indent,
          allow_prefixed_blocks=has_paragraph_content,
        ) {
    ()
  }
  while try_parse_list_item_indented_flow(ctx, context) {
    ()
  }
  while try_continue_list_item_after_blank_line(
          ctx,
          context,
          allow_paragraph_continuation=has_paragraph_content,
        ) {
    ()
  }
  while try_parse_list_item_indented_flow(ctx, context) {
    ()
  }
  let nested_flow_consumed = parse_nested_list_item_flow(
    ctx,
    context.content_indent,
  )
  if nested_flow_consumed {
    while try_continue_list_item_after_blank_line(
            ctx,
            context,
            allow_paragraph_continuation=true,
          ) {
      ()
    }
  }
}

///|
fn parse_list_item_code_fence_tail(
  ctx : @core.ParserContext[Token, SyntaxKind],
  context : ListItemFlowContext,
) -> Unit {
  while try_continue_list_item_after_blank_line(
          ctx,
          context,
          allow_paragraph_continuation=true,
        ) {
    ()
  }
  while try_parse_list_item_indented_flow(ctx, context) {
    ()
  }
}

///|
fn parse_list_item_body(
  ctx : @core.ParserContext[Token, SyntaxKind],
  content_indent : Int,
  marker_end_column : Int,
  allow_ordered_marker~ : Bool,
) -> Unit {
  let context = ListItemFlowContext::{
    content_indent,
    marker_end_column,
    allow_ordered_marker,
  }
  let starts_reference_definition = current_line_is_link_reference_definition(
    ctx,
  )
  let has_paragraph_content = !starts_reference_definition &&
    list_item_line_starts_paragraph(ctx)
  match ctx.peek() {
    ListMarker => {
      parse_list_at_min_indent_with_first_item_column(
        ctx,
        0,
        Some(context.content_indent),
      )
      parse_list_item_flow_after_body(ctx, context, true)
      return
    }
    OrderedListMarker(_) => {
      parse_ordered_list_at_min_indent_with_first_item_column(
        ctx,
        0,
        Some(context.content_indent),
      )
      parse_list_item_flow_after_body(ctx, context, true)
      return
    }
    BlockQuoteMarker => {
      parse_block_quote_with_prefix(ctx, None, ListOwned(content_indent))
      parse_list_item_flow_after_body(ctx, context, true)
      return
    }
    CodeFenceOpen(_, _) => {
      parse_code_block(ctx)
      parse_list_item_code_fence_tail(ctx, context)
      return
    }
    HeadingMarker(_) => {
      parse_heading(ctx)
      parse_list_item_flow_after_body(ctx, context, true)
      return
    }
    _ => ()
  }
  if starts_reference_definition {
    parse_link_reference_definition(ctx)
  } else if current_text_reaches_indented_code_column(
      ctx, marker_end_column, content_indent,
    ) {
    parse_indented_code_block_from_current_line(
      ctx,
      min_indent=marker_end_column + 4,
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
    ignore(try_continue_empty_list_item_after_newline(ctx, context))
  }
  if ctx.peek() is Newline &&
    ctx.peek_nth(1) is BlockQuoteMarker &&
    ctx.peek_nth(2) is BlockQuoteMarker {
    ignore(try_parse_list_item_quoted_blank_line_continuation(ctx, context))
  }
  parse_list_item_flow_after_body(ctx, context, has_paragraph_content)
}

///|
/// Parse a single list item: ListMarker followed by inline content.
fn parse_list_item_with_marker_start_column(
  ctx : @core.ParserContext[Token, SyntaxKind],
  marker_start_column : Int?,
) -> Unit {
  ctx.node(ListItemNode, fn() {
    let marker_start_column = match marker_start_column {
      Some(column) => column
      None => consume_list_item_prefix(ctx)
    }
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
fn parse_list_item(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_list_item_with_marker_start_column(ctx, None)
}

///|
/// Parse an ordered list: one or more ListItems using the same delimiter.
fn parse_ordered_list(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  parse_ordered_list_at_min_indent(ctx, 0)
}

///|
/// The ordered-list counterpart preserves the same inline marker-column rule
/// when an ordered list is nested directly in a list item.
fn parse_ordered_list_at_min_indent_with_first_item_column(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
  first_item_marker_start_column : Int?,
) -> Unit {
  ctx.node(OrderedListNode, fn() {
    match current_ordered_list_marker(ctx) {
      Some(opening_marker) =>
        parse_list_items_at_min_indent(
          ctx,
          Ordered(opening_marker),
          min_indent,
          first_item_marker_start_column,
        )
      None => ()
    }
  })
}

///|
fn parse_ordered_list_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
) -> Unit {
  parse_ordered_list_at_min_indent_with_first_item_column(ctx, min_indent, None)
}

///|
/// Parse a single ordered list item: OrderedListMarker followed by inline content.
fn parse_ordered_list_item_with_marker_start_column(
  ctx : @core.ParserContext[Token, SyntaxKind],
  marker_start_column : Int?,
) -> Unit {
  ctx.node(ListItemNode, fn() {
    let marker_start_column = match marker_start_column {
      Some(column) => column
      None => consume_list_item_prefix(ctx)
    }
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
fn parse_ordered_list_item(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  parse_ordered_list_item_with_marker_start_column(ctx, None)
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

///|
fn consume_html_block_html_text_body(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
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
}

///|
fn parse_html_block(
  ctx : @core.ParserContext[Token, SyntaxKind],
  prefix : LinePrefix?,
) -> Unit {
  let open_token = match prefix {
    Some(_) => ctx.peek_nth(1)
    None => ctx.peek()
  }
  let open_kind = match open_token {
    HtmlBlockOpen(_, kind) => kind
    _ => abort("parse_html_block expected HtmlBlockOpen")
  }
  ctx.node(HtmlBlockNode, fn() {
    match prefix {
      Some(_) => ctx.emit_token(IndentationToken)
      None => ()
    }
    ctx.emit_token(HtmlBlockOpenToken)
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
    match open_kind {
      Type6 => {
        // HtmlText body until blank / EOF (lexer HtmlBlockRaw).
        consume_html_block_html_text_body(ctx)
        while ctx.peek() is Newline {
          ctx.emit_token(NewlineToken)
        }
      }
      Type7 =>
        // Type 7 leaves LineStart after open, so body lines are ordinary
        // tokens until blank / EOF (deferred body under ModeLexer).
        while !(ctx.peek() is BlankLine) && ctx.peek() != EOF {
          match ctx.peek() {
            Newline => ctx.emit_token(NewlineToken)
            HtmlText(_) => ctx.emit_token(HtmlTextToken)
            _ => ctx.emit_token(TextToken)
          }
        }
      Until(_) => {
        // Types 1–5: HtmlText body until closing delimiter (or EOF).
        consume_html_block_html_text_body(ctx)
        // Trailing newline run before EOF: when a delimiter-terminated block
        // runs to end-of-document without finding its closing tag, blank lines
        // at the end are part of the block content, not structural separators.
        while ctx.peek() is Newline {
          ctx.emit_token(NewlineToken)
        }
      }
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
    }
  })
}

///|
fn parse_quoted_code_block_with_prefix(
  ctx : @core.ParserContext[Token, SyntaxKind],
  prefix : LinePrefix?,
) -> Unit {
  ctx.node(CodeBlockNode, fn() {
    match prefix {
      Some(_) => ctx.emit_token(IndentationToken)
      None => ()
    }
    ctx.emit_token(CodeFenceOpenToken)
    while ctx.peek() != EOF {
      match ctx.peek() {
        CodeFenceClose => {
          ctx.emit_token(CodeFenceCloseToken)
          if ctx.peek() is Newline {
            ctx.emit_token(NewlineToken)
          }
          break
        }
        CodeText(_) => ctx.emit_token(CodeTextToken)
        Indentation(_) if ctx.peek_nth(1) is BlockQuoteMarker =>
          ctx.emit_token(IndentationToken)
        BlockQuoteMarker => ctx.emit_token(BlockQuoteMarkerToken)
        Newline => ctx.emit_token(NewlineToken)
        BlankLine | _ => break
      }
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
    consume_indented_code_body(ctx, min_indent)
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

///|
/// Blockquote-owned indented code. Continues across marked lines; stops at
/// unmarked breaks (CommonMark examples 236, 252).
fn parse_quoted_indented_code_block_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  min_indent : Int,
  ownership : BlockQuotePrefixOwnership,
) -> Unit {
  ctx.node(CodeBlockNode, fn() {
    consume_quoted_indented_code_body(ctx, min_indent, ownership)
  })
}

///|
fn parse_quoted_indented_code_block(
  ctx : @core.ParserContext[Token, SyntaxKind],
  ownership~ : BlockQuotePrefixOwnership,
) -> Unit {
  parse_quoted_indented_code_block_at_min_indent(ctx, 4, ownership)
}
