///|
fn continuation_context(
  source_id : @core.SourceId,
  source : String,
) -> @core.ParserContext[Token, SyntaxKind] {
  let tokens = tokenize(source) catch {
    _ => abort("continuation test tokenization failed")
  }
  @core.ParserContext::new(source_id, tokens, source, markdown_spec)
}

///|
/// Advance to the first Newline softbreak. A source that begins with `\n`
/// tokenizes that leading break as BlankLine, which is not the observation
/// point used by the inline continuation driver.
fn seek_continuation_newline(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  while !(ctx.peek() is Newline) && ctx.peek() != EOF {
    match ctx.peek() {
      BlankLine => ctx.emit_token(BlankLineToken)
      Text(_) => ctx.emit_token(TextToken)
      Indentation(_) => ctx.emit_token(IndentationToken)
      _ => abort("continuation fixture could not reach newline")
    }
  }
  guard ctx.peek() is Newline else {
    abort("continuation fixture source lacks a newline softbreak")
  }
}

///|
fn continuation_context_at_newline(
  source_id : @core.SourceId,
  source : String,
) -> @core.ParserContext[Token, SyntaxKind] {
  let ctx = continuation_context(source_id, source)
  seek_continuation_newline(ctx)
  ctx
}

///|
fn assert_decision_public_state_pure(
  ctx : @core.ParserContext[Token, SyntaxKind],
  decision : () -> Unit,
) -> Unit raise {
  let before_range = ctx.current_token_range()
  let before_node = ctx.current_node_kind()
  let before_mark = ctx.mark()
  decision()
  let after_mark = ctx.mark()
  inspect(ctx.current_token_range(), content=before_range.to_string())
  inspect(
    @debug.to_string(ctx.current_node_kind()),
    content=@debug.to_string(before_node),
  )
  inspect(after_mark, content=(before_mark + 1).to_string())
}

///|
test "continuation decisions: root variants" {
  let source_id = @core.SourceId("markdown-continuation-root-variants")
  let no_prefix = continuation_context_at_newline(source_id, "para\nbar\n")
  assert_decision_public_state_pure(no_prefix, () => {
    match decide_root_paragraph_continuation(no_prefix) {
      Continue(ContinueNoPrefix) => ()
      _ => abort("expected root NoPrefix")
    }
  })

  // Indented thematic-break-looking line (indent >= 4) continues as text.
  // Bare "\n---\n" / "\n ---\n" stop via prefix dispatch or block boundary.
  let thematic = continuation_context_at_newline(source_id, "para\n    ---\n")
  assert_decision_public_state_pure(thematic, () => {
    match decide_root_paragraph_continuation(thematic) {
      Continue(ContinueThematicBreakPrefix) => ()
      _ => abort("expected root ThematicBreakPrefix")
    }
  })

  // Lone list marker continues as text; "\n- item\n" interrupts as a list.
  let list_marker = continuation_context_at_newline(source_id, "para\n-\n")
  assert_decision_public_state_pure(list_marker, () => {
    match decide_root_paragraph_continuation(list_marker) {
      Continue(ContinueListMarkerPrefix) => ()
      _ => abort("expected root ListMarkerPrefix")
    }
  })

  // Ordered markers with start != 1 are ListMarkerPrefix continuations.
  let ordered = continuation_context_at_newline(source_id, "para\n2. x\n")
  assert_decision_public_state_pure(ordered, () => {
    match decide_root_paragraph_continuation(ordered) {
      Continue(ContinueListMarkerPrefix) => ()
      _ => abort("expected root ListMarkerPrefix for non-1 ordered marker")
    }
  })
}

///|
test "continuation decisions: root Stop" {
  let source_id = @core.SourceId("markdown-continuation-root-stop")
  let blank = continuation_context_at_newline(source_id, "para\n\n")
  assert_decision_public_state_pure(blank, () => {
    match decide_root_paragraph_continuation(blank) {
      Stop => ()
      _ => abort("expected root Stop for blank line")
    }
  })

  let thematic = continuation_context_at_newline(source_id, "para\n---\n")
  assert_decision_public_state_pure(thematic, () => {
    match decide_root_paragraph_continuation(thematic) {
      Stop => ()
      _ => abort("expected root Stop for bare thematic break")
    }
  })

  let list_item = continuation_context_at_newline(source_id, "para\n- item\n")
  assert_decision_public_state_pure(list_item, () => {
    match decide_root_paragraph_continuation(list_item) {
      Stop => ()
      _ => abort("expected root Stop for list item")
    }
  })

  let ordered_one = continuation_context_at_newline(source_id, "para\n1. x\n")
  assert_decision_public_state_pure(ordered_one, () => {
    match decide_root_paragraph_continuation(ordered_one) {
      Stop => ()
      _ => abort("expected root Stop for ordered start 1")
    }
  })
}

///|
test "continuation decisions: setext variants" {
  let source_id = @core.SourceId("markdown-continuation-setext-variants")
  let no_prefix = continuation_context_at_newline(source_id, "para\nbar\n")
  assert_decision_public_state_pure(no_prefix, () => {
    match decide_setext_continuation(no_prefix) {
      Continue(ContinueNoPrefix) => ()
      _ => abort("expected setext NoPrefix")
    }
  })

  // Ordered marker at the post-newline cursor becomes text when start != 1.
  let ordered = continuation_context_at_newline(source_id, "para\n2. x\n")
  assert_decision_public_state_pure(ordered, () => {
    match decide_setext_continuation(ordered) {
      Continue(ContinueOrderedMarkerAsText) => ()
      _ => abort("expected setext OrderedMarkerAsText")
    }
  })
}

///|
test "continuation decisions: setext Stop" {
  let source_id = @core.SourceId("markdown-continuation-setext-stop")
  let not_newline = continuation_context(source_id, "bar\n")
  assert_decision_public_state_pure(not_newline, () => {
    match decide_setext_continuation(not_newline) {
      Stop => ()
      _ => abort("expected setext Stop when not at newline")
    }
  })

  let underline = continuation_context_at_newline(source_id, "para\n===\n")
  assert_decision_public_state_pure(underline, () => {
    match decide_setext_continuation(underline) {
      Stop => ()
      _ => abort("expected setext Stop for underline")
    }
  })

  let thematic = continuation_context_at_newline(source_id, "para\n---\n")
  assert_decision_public_state_pure(thematic, () => {
    match decide_setext_continuation(thematic) {
      Stop => ()
      _ => abort("expected setext Stop for thematic underline")
    }
  })

  let ordered_one = continuation_context_at_newline(source_id, "para\n1. x\n")
  assert_decision_public_state_pure(ordered_one, () => {
    match decide_setext_continuation(ordered_one) {
      Stop => ()
      _ => abort("expected setext Stop for ordered start 1")
    }
  })
}

///|
test "continuation decisions: block-quote variants" {
  let source_id = @core.SourceId("markdown-continuation-block-quote-variants")
  let marker_no_prefix = continuation_context_at_newline(
    source_id, "para\n> bar\n",
  )
  assert_decision_public_state_pure(marker_no_prefix, () => {
    match decide_block_quote_paragraph_continuation(marker_no_prefix) {
      Continue(ContinueQuoteMarker(ContinuationPrefixKind::NoPrefix)) => ()
      _ => abort("expected MarkerAndPrefix(NoPrefix)")
    }
  })

  // Indented thematic-break-looking line after `>` continues as text.
  let marker_thematic = continuation_context_at_newline(
    source_id, "para\n>    ---\n",
  )
  assert_decision_public_state_pure(marker_thematic, () => {
    match decide_block_quote_paragraph_continuation(marker_thematic) {
      Continue(ContinueQuoteMarker(ThematicBreakPrefix)) => ()
      _ => abort("expected MarkerAndPrefix(ThematicBreakPrefix)")
    }
  })

  // Ordered markers with start != 1 continue as text after `>`.
  let marker_list = continuation_context_at_newline(source_id, "para\n>2. x\n")
  assert_decision_public_state_pure(marker_list, () => {
    match decide_block_quote_paragraph_continuation(marker_list) {
      Continue(ContinueQuoteMarker(ListMarkerPrefix)) => ()
      _ => abort("expected MarkerAndPrefix(ListMarkerPrefix)")
    }
  })

  // Four or more literal columns before `>` are not an explicit quote
  // continuation marker.
  let over_indented_marker = continuation_context_at_newline(
    source_id, "para\n    > bar\n",
  )
  assert_decision_public_state_pure(over_indented_marker, () => {
    match decide_block_quote_paragraph_continuation(over_indented_marker) {
      Continue(ContinueQuoteMarker(_)) =>
        abort("over-indented quote must not be an explicit marker")
      _ => ()
    }
  })

  let prefix_only = continuation_context_at_newline(source_id, "para\nbar\n")
  assert_decision_public_state_pure(prefix_only, () => {
    match decide_block_quote_paragraph_continuation(prefix_only) {
      Continue(ContinueQuoteLazy(ContinuationPrefixKind::NoPrefix)) => ()
      _ => abort("expected PrefixOnly(NoPrefix)")
    }
  })

  let prefix_thematic = continuation_context_at_newline(
    source_id, "para\n    ---\n",
  )
  assert_decision_public_state_pure(prefix_thematic, () => {
    match decide_block_quote_paragraph_continuation(prefix_thematic) {
      Continue(ContinueQuoteLazy(ThematicBreakPrefix)) => ()
      _ => abort("expected PrefixOnly(ThematicBreakPrefix)")
    }
  })

  let prefix_list = continuation_context_at_newline(source_id, "para\n2. x\n")
  assert_decision_public_state_pure(prefix_list, () => {
    match decide_block_quote_paragraph_continuation(prefix_list) {
      Continue(ContinueQuoteLazy(ListMarkerPrefix)) => ()
      _ => abort("expected PrefixOnly(ListMarkerPrefix)")
    }
  })
}

///|
test "continuation decisions: block-quote Stop" {
  let source_id = @core.SourceId("markdown-continuation-block-quote-stop")
  let thematic = continuation_context_at_newline(source_id, "para\n---\n")
  assert_decision_public_state_pure(thematic, () => {
    match decide_block_quote_paragraph_continuation(thematic) {
      Stop => ()
      _ => abort("expected block-quote Stop for thematic break")
    }
  })

  let list_item = continuation_context_at_newline(source_id, "para\n- item\n")
  assert_decision_public_state_pure(list_item, () => {
    match decide_block_quote_paragraph_continuation(list_item) {
      Stop => ()
      _ => abort("expected block-quote Stop for list item")
    }
  })
}

///|
test "continuation decisions: block-quote setext variants" {
  let source_id = @core.SourceId(
    "markdown-continuation-block-quote-setext-variants",
  )
  let marker = continuation_context_at_newline(source_id, "para\n> bar\n")
  assert_decision_public_state_pure(marker, () => {
    match decide_block_quote_heading_continuation(marker) {
      Continue(ContinueQuoteMarker(ContinuationPrefixKind::NoPrefix)) => ()
      _ => abort("expected block-quote setext MarkerAndPrefix(NoPrefix)")
    }
  })

  let ordered = continuation_context_at_newline(source_id, "para\n>2. x\n")
  assert_decision_public_state_pure(ordered, () => {
    match decide_block_quote_heading_continuation(ordered) {
      Continue(ContinueQuoteMarker(ListMarkerPrefix)) => ()
      _ =>
        abort("expected block-quote setext MarkerAndPrefix(ListMarkerPrefix)")
    }
  })
}

///|
test "continuation decisions: block-quote setext Stop" {
  let source_id = @core.SourceId(
    "markdown-continuation-block-quote-setext-stop",
  )
  let not_newline = continuation_context(source_id, "bar\n")
  assert_decision_public_state_pure(not_newline, () => {
    match decide_block_quote_heading_continuation(not_newline) {
      Stop => ()
      _ => abort("expected block-quote setext Stop when not at newline")
    }
  })

  let underline = continuation_context_at_newline(source_id, "para\n> ===\n")
  assert_decision_public_state_pure(underline, () => {
    match decide_block_quote_heading_continuation(underline) {
      Stop => ()
      _ => abort("expected block-quote setext Stop for underline")
    }
  })

  let thematic_underline = continuation_context_at_newline(
    source_id, "para\n> ---\n",
  )
  assert_decision_public_state_pure(thematic_underline, () => {
    match decide_block_quote_heading_continuation(thematic_underline) {
      Stop => ()
      _ => abort("expected block-quote setext Stop for thematic underline")
    }
  })
}

///|
test "continuation decisions: list-item variants" {
  let source_id = @core.SourceId("markdown-continuation-list-item-variants")
  let no_prefix = continuation_context_at_newline(source_id, "para\nchild\n")
  assert_decision_public_state_pure(no_prefix, () => {
    match
      decide_list_item_continuation(
        no_prefix,
        2,
        allow_ordered_marker=true,
        has_paragraph_content=true,
      ) {
      Continue(ContinueNoPrefix) => ()
      _ => abort("expected list-item NoPrefix")
    }
  })

  let indentation = continuation_context_at_newline(
    source_id, "para\n  child\n",
  )
  assert_decision_public_state_pure(indentation, () => {
    match
      decide_list_item_continuation(
        indentation,
        2,
        allow_ordered_marker=true,
        has_paragraph_content=true,
      ) {
      Continue(ContinueIndentationPrefix) => ()
      _ => abort("expected list-item IndentationPrefix")
    }
  })

  let ordered = continuation_context_at_newline(source_id, "para\n2. child\n")
  assert_decision_public_state_pure(ordered, () => {
    match
      decide_list_item_continuation(
        ordered,
        2,
        allow_ordered_marker=true,
        has_paragraph_content=true,
      ) {
      Continue(ContinueOrderedMarkerAsText) => ()
      _ => abort("expected list-item OrderedMarkerAsText")
    }
  })
}

///|
test "continuation decisions: list-item Stop" {
  let source_id = @core.SourceId("markdown-continuation-list-item-stop")
  let no_paragraph = continuation_context_at_newline(source_id, "para\nchild\n")
  assert_decision_public_state_pure(no_paragraph, () => {
    match
      decide_list_item_continuation(
        no_paragraph,
        2,
        allow_ordered_marker=true,
        has_paragraph_content=false,
      ) {
      Stop => ()
      _ => abort("expected list-item Stop without paragraph content")
    }
  })

  let boundary = continuation_context_at_newline(source_id, "para\n# heading\n")
  assert_decision_public_state_pure(boundary, () => {
    match
      decide_list_item_continuation(
        boundary,
        2,
        allow_ordered_marker=true,
        has_paragraph_content=true,
      ) {
      Stop => ()
      _ => abort("expected list-item Stop at block boundary")
    }
  })
}

///|
test "continuation decisions: list-item setext variants" {
  let source_id = @core.SourceId(
    "markdown-continuation-list-item-setext-variants",
  )
  let no_prefix = continuation_context_at_newline(source_id, "para\nchild\n")
  assert_decision_public_state_pure(no_prefix, () => {
    match
      decide_list_item_setext_continuation(
        no_prefix,
        2,
        allow_ordered_marker=true,
      ) {
      Continue(ContinueNoPrefix) => ()
      _ => abort("expected list-item setext NoPrefix")
    }
  })

  let indentation = continuation_context_at_newline(
    source_id, "para\n  child\n",
  )
  assert_decision_public_state_pure(indentation, () => {
    match
      decide_list_item_setext_continuation(
        indentation,
        2,
        allow_ordered_marker=true,
      ) {
      Continue(ContinueIndentationPrefix) => ()
      _ => abort("expected list-item setext IndentationPrefix")
    }
  })

  let ordered = continuation_context_at_newline(source_id, "para\n2. child\n")
  assert_decision_public_state_pure(ordered, () => {
    match
      decide_list_item_setext_continuation(
        ordered,
        2,
        allow_ordered_marker=true,
      ) {
      Continue(ContinueOrderedMarkerAsText) => ()
      _ => abort("expected list-item setext OrderedMarkerAsText")
    }
  })
}

///|
test "continuation decisions: list-item setext Stop" {
  let source_id = @core.SourceId("markdown-continuation-list-item-setext-stop")
  let underline = continuation_context_at_newline(source_id, "para\n===\n")
  assert_decision_public_state_pure(underline, () => {
    match
      decide_list_item_setext_continuation(
        underline,
        0,
        allow_ordered_marker=true,
      ) {
      Stop => ()
      _ => abort("expected list-item setext Stop for underline")
    }
  })

  let boundary = continuation_context_at_newline(source_id, "para\n# heading\n")
  assert_decision_public_state_pure(boundary, () => {
    match
      decide_list_item_setext_continuation(
        boundary,
        2,
        allow_ordered_marker=true,
      ) {
      Stop => ()
      _ => abort("expected list-item setext Stop at block boundary")
    }
  })
}

///|
/// The combined code/delimiter analysis and actual inline pass must invoke the
/// same typed continuation action. External counters observe both passes even
/// though ParserContext restores its own state after the lookahead.
test "continuation driver: analysis and actual passes consume same action" {
  let source_id = @core.SourceId("markdown-continuation-driver-pass-parity")
  let ctx = continuation_context(source_id, "para\nchild\n")
  let consume_calls = [0]
  let no_prefix_calls = [0]
  let handler : ContinuationHandler[BlockContinuationAction] = {
    decide: () => decide_root_paragraph_continuation(ctx),
    consume: action => {
      consume_calls[0] = consume_calls[0] + 1
      match action {
        ContinueNoPrefix => no_prefix_calls[0] = no_prefix_calls[0] + 1
        _ => abort("expected NoPrefix in both parser passes")
      }
      consume_block_continuation(ctx, action)
    },
  }
  parse_indexed_inline_container(ctx, InlineParsePolicy::paragraph(), handler)
  inspect(consume_calls[0], content="2")
  inspect(no_prefix_calls[0], content="2")
}
