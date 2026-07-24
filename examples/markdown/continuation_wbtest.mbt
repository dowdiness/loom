///|
fn continuation_context(
  source : String,
) -> @core.ParserContext[Token, SyntaxKind] {
  let tokens = tokenize(source) catch {
    _ => abort("continuation test tokenization failed")
  }
  @core.ParserContext::new(tokens, source, markdown_spec)
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
  source : String,
) -> @core.ParserContext[Token, SyntaxKind] {
  let ctx = continuation_context(source)
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
  let before_mode = ctx.lex_mode()
  let before_mark = ctx.mark()
  decision()
  let after_mark = ctx.mark()
  inspect(ctx.current_token_range(), content=before_range.to_string())
  inspect(
    @debug.to_string(ctx.current_node_kind()),
    content=@debug.to_string(before_node),
  )
  inspect(ctx.lex_mode(), content=before_mode.to_string())
  inspect(after_mark, content=(before_mark + 1).to_string())
}
///|
test "continuation facts: root observer mirrors decisions" {
  let no_prefix = continuation_context_at_newline("para\nbar\n")
  let no_prefix_offset = no_prefix.current_token_range().start
  match observe_root_paragraph_continuation(no_prefix, no_prefix_offset) {
    Continue(RootContinuationKind::NoPrefix) => ()
    _ => abort("expected fact-observed root NoPrefix")
  }

  let thematic = continuation_context_at_newline("para\n    ---\n")
  let thematic_offset = thematic.current_token_range().start
  match observe_root_paragraph_continuation(thematic, thematic_offset) {
    Continue(RootContinuationKind::ThematicBreakPrefix) => ()
    _ => abort("expected fact-observed root ThematicBreakPrefix")
  }

  let boundary = continuation_context_at_newline("para\n---\n")
  let boundary_offset = boundary.current_token_range().start
  match observe_root_paragraph_continuation(boundary, boundary_offset) {
    Stop => ()
    _ => abort("expected fact-observed root Stop")
  }
}

///|
test "continuation facts: block-quote prefix-only thematic line stops" {
  let ctx = continuation_context_at_newline("para\n---\n")
  let offset = ctx.current_token_range().start
  match observe_block_quote_paragraph_continuation(ctx, offset) {
    Stop => ()
    _ => abort("expected fact-observed block-quote thematic line Stop")
  }
}
///|
test "continuation facts: setext observers mirror decisions" {
  let root = continuation_context_at_newline("para\nbar\n")
  match observe_setext_continuation(root, root.current_token_range().start) {
    Continue(SetextContinuationKind::NoPrefix) => ()
    _ => abort("expected fact-observed setext NoPrefix")
  }

  let quoted = continuation_context_at_newline("para\n> bar\n")
  match observe_block_quote_heading_continuation(
    quoted,
    quoted.current_token_range().start,
  ) {
    Continue(BlockQuoteHeadingContinuationKind::MarkerAndPrefix(NoPrefix)) => ()
    _ => abort("expected fact-observed quoted setext MarkerAndPrefix(NoPrefix)")
  }

  let quoted_underline = continuation_context_at_newline("para\n> ---\n")
  match observe_block_quote_heading_continuation(
    quoted_underline,
    quoted_underline.current_token_range().start,
  ) {
    Stop => ()
    _ => abort("expected fact-observed quoted setext underline Stop")
  }
}

///|
test "continuation facts: list observers mirror decisions" {
  let item = continuation_context_at_newline("para\n  child\n")
  match observe_list_item_continuation(
    item,
    item.current_token_range().start,
    2,
    allow_ordered_marker=true,
    has_paragraph_content=true,
  ) {
    Continue(ListItemContinuationKind::IndentationPrefix) => ()
    _ => abort("expected fact-observed list indentation prefix")
  }

  let setext = continuation_context_at_newline("para\n2. child\n")
  match observe_list_item_setext_continuation(
    setext,
    setext.current_token_range().start,
    2,
    allow_ordered_marker=true,
  ) {
    Continue(ListItemSetextContinuationKind::OrderedMarkerAsText) => ()
    _ => abort("expected fact-observed list setext ordered marker")
  }

  let unindented_underline = continuation_context_at_newline("para\n---\n")
  match observe_list_item_setext_continuation(
    unindented_underline,
    unindented_underline.current_token_range().start,
    2,
    allow_ordered_marker=true,
  ) {
    Stop => ()
    _ => abort("expected fact-observed list setext Stop for unindented underline")
  }

  match setext_underline_depth_after_newline_at(
    unindented_underline,
    unindented_underline.current_token_range().start,
    allow_list_marker=false,
    min_indent=2,
  ) {
    None => ()
    _ => abort("unindented thematic fact must not satisfy list indentation")
  }

  let indented_underline = continuation_context_at_newline("para\n  ---\n")
  match setext_underline_depth_after_newline_at(
    indented_underline,
    indented_underline.current_token_range().start,
    allow_list_marker=false,
    min_indent=2,
  ) {
    Some(2) => ()
    _ => abort("indented thematic fact must satisfy list indentation")
  }
}

///|
test "continuation decisions: root variants" {
  let no_prefix = continuation_context_at_newline("para\nbar\n")
  assert_decision_public_state_pure(no_prefix, () => {
    match decide_root_paragraph_continuation(no_prefix) {
      Continue(RootContinuationKind::NoPrefix) => ()
      _ => abort("expected root NoPrefix")
    }
  })

  // Indented thematic-break-looking line (indent >= 4) continues as text.
  // Bare "\n---\n" / "\n ---\n" stop via prefix dispatch or block boundary.
  let thematic = continuation_context_at_newline("para\n    ---\n")
  assert_decision_public_state_pure(thematic, () => {
    match decide_root_paragraph_continuation(thematic) {
      Continue(ThematicBreakPrefix) => ()
      _ => abort("expected root ThematicBreakPrefix")
    }
  })

  // Lone list marker continues as text; "\n- item\n" interrupts as a list.
  let list_marker = continuation_context_at_newline("para\n-\n")
  assert_decision_public_state_pure(list_marker, () => {
    match decide_root_paragraph_continuation(list_marker) {
      Continue(ListMarkerPrefix) => ()
      _ => abort("expected root ListMarkerPrefix")
    }
  })

  // Ordered markers with start != 1 are ListMarkerPrefix continuations.
  let ordered = continuation_context_at_newline("para\n2. x\n")
  assert_decision_public_state_pure(ordered, () => {
    match decide_root_paragraph_continuation(ordered) {
      Continue(ListMarkerPrefix) => ()
      _ => abort("expected root ListMarkerPrefix for non-1 ordered marker")
    }
  })
}

///|
test "continuation decisions: root Stop" {
  let blank = continuation_context_at_newline("para\n\n")
  assert_decision_public_state_pure(blank, () => {
    match decide_root_paragraph_continuation(blank) {
      Stop => ()
      _ => abort("expected root Stop for blank line")
    }
  })

  let thematic = continuation_context_at_newline("para\n---\n")
  assert_decision_public_state_pure(thematic, () => {
    match decide_root_paragraph_continuation(thematic) {
      Stop => ()
      _ => abort("expected root Stop for bare thematic break")
    }
  })

  let list_item = continuation_context_at_newline("para\n- item\n")
  assert_decision_public_state_pure(list_item, () => {
    match decide_root_paragraph_continuation(list_item) {
      Stop => ()
      _ => abort("expected root Stop for list item")
    }
  })

  let ordered_one = continuation_context_at_newline("para\n1. x\n")
  assert_decision_public_state_pure(ordered_one, () => {
    match decide_root_paragraph_continuation(ordered_one) {
      Stop => ()
      _ => abort("expected root Stop for ordered start 1")
    }
  })
}

///|
test "continuation decisions: setext variants" {
  let no_prefix = continuation_context_at_newline("para\nbar\n")
  assert_decision_public_state_pure(no_prefix, () => {
    match decide_setext_continuation(no_prefix) {
      Continue(SetextContinuationKind::NoPrefix) => ()
      _ => abort("expected setext NoPrefix")
    }
  })

  // Ordered marker at the post-newline cursor becomes text when start != 1.
  let ordered = continuation_context_at_newline("para\n2. x\n")
  assert_decision_public_state_pure(ordered, () => {
    match decide_setext_continuation(ordered) {
      Continue(OrderedMarkerAsText) => ()
      _ => abort("expected setext OrderedMarkerAsText")
    }
  })
}

///|
test "continuation decisions: setext Stop" {
  let not_newline = continuation_context("bar\n")
  assert_decision_public_state_pure(not_newline, () => {
    match decide_setext_continuation(not_newline) {
      Stop => ()
      _ => abort("expected setext Stop when not at newline")
    }
  })

  let underline = continuation_context_at_newline("para\n===\n")
  assert_decision_public_state_pure(underline, () => {
    match decide_setext_continuation(underline) {
      Stop => ()
      _ => abort("expected setext Stop for underline")
    }
  })

  let thematic = continuation_context_at_newline("para\n---\n")
  assert_decision_public_state_pure(thematic, () => {
    match decide_setext_continuation(thematic) {
      Stop => ()
      _ => abort("expected setext Stop for thematic underline")
    }
  })

  let ordered_one = continuation_context_at_newline("para\n1. x\n")
  assert_decision_public_state_pure(ordered_one, () => {
    match decide_setext_continuation(ordered_one) {
      Stop => ()
      _ => abort("expected setext Stop for ordered start 1")
    }
  })
}

///|
test "continuation decisions: block-quote variants" {
  let marker_no_prefix = continuation_context_at_newline("para\n> bar\n")
  assert_decision_public_state_pure(marker_no_prefix, () => {
    match decide_block_quote_paragraph_continuation(marker_no_prefix) {
      Continue(MarkerAndPrefix(ContinuationPrefixKind::NoPrefix)) => ()
      _ => abort("expected MarkerAndPrefix(NoPrefix)")
    }
  })

  // Indented thematic-break-looking line after `>` continues as text.
  let marker_thematic = continuation_context_at_newline("para\n>    ---\n")
  assert_decision_public_state_pure(marker_thematic, () => {
    match decide_block_quote_paragraph_continuation(marker_thematic) {
      Continue(MarkerAndPrefix(ThematicBreakPrefix)) => ()
      _ => abort("expected MarkerAndPrefix(ThematicBreakPrefix)")
    }
  })

  // Ordered markers with start != 1 continue as text after `>`.
  let marker_list = continuation_context_at_newline("para\n>2. x\n")
  assert_decision_public_state_pure(marker_list, () => {
    match decide_block_quote_paragraph_continuation(marker_list) {
      Continue(MarkerAndPrefix(ListMarkerPrefix)) => ()
      _ => abort("expected MarkerAndPrefix(ListMarkerPrefix)")
    }
  })

  let prefix_only = continuation_context_at_newline("para\nbar\n")
  assert_decision_public_state_pure(prefix_only, () => {
    match decide_block_quote_paragraph_continuation(prefix_only) {
      Continue(PrefixOnly(ContinuationPrefixKind::NoPrefix)) => ()
      _ => abort("expected PrefixOnly(NoPrefix)")
    }
  })

  let prefix_thematic = continuation_context_at_newline("para\n    ---\n")
  assert_decision_public_state_pure(prefix_thematic, () => {
    match decide_block_quote_paragraph_continuation(prefix_thematic) {
      Continue(PrefixOnly(ThematicBreakPrefix)) => ()
      _ => abort("expected PrefixOnly(ThematicBreakPrefix)")
    }
  })

  let prefix_list = continuation_context_at_newline("para\n2. x\n")
  assert_decision_public_state_pure(prefix_list, () => {
    match decide_block_quote_paragraph_continuation(prefix_list) {
      Continue(PrefixOnly(ListMarkerPrefix)) => ()
      _ => abort("expected PrefixOnly(ListMarkerPrefix)")
    }
  })
}

///|
test "continuation decisions: block-quote Stop" {
  let thematic = continuation_context_at_newline("para\n---\n")
  assert_decision_public_state_pure(thematic, () => {
    match decide_block_quote_paragraph_continuation(thematic) {
      Stop => ()
      _ => abort("expected block-quote Stop for thematic break")
    }
  })

  let list_item = continuation_context_at_newline("para\n- item\n")
  assert_decision_public_state_pure(list_item, () => {
    match decide_block_quote_paragraph_continuation(list_item) {
      Stop => ()
      _ => abort("expected block-quote Stop for list item")
    }
  })
}

///|
test "continuation decisions: block-quote setext variants" {
  let marker = continuation_context_at_newline("para\n> bar\n")
  assert_decision_public_state_pure(marker, () => {
    match decide_block_quote_heading_continuation(marker) {
      Continue(
        BlockQuoteHeadingContinuationKind::MarkerAndPrefix(
          ContinuationPrefixKind::NoPrefix
        )
      ) => ()
      _ => abort("expected block-quote setext MarkerAndPrefix(NoPrefix)")
    }
  })

  let ordered = continuation_context_at_newline("para\n>2. x\n")
  assert_decision_public_state_pure(ordered, () => {
    match decide_block_quote_heading_continuation(ordered) {
      Continue(
        BlockQuoteHeadingContinuationKind::MarkerAndPrefix(ListMarkerPrefix)
      ) => ()
      _ =>
        abort("expected block-quote setext MarkerAndPrefix(ListMarkerPrefix)")
    }
  })
}

///|
test "continuation decisions: block-quote setext Stop" {
  let not_newline = continuation_context("bar\n")
  assert_decision_public_state_pure(not_newline, () => {
    match decide_block_quote_heading_continuation(not_newline) {
      Stop => ()
      _ => abort("expected block-quote setext Stop when not at newline")
    }
  })

  let underline = continuation_context_at_newline("para\n> ===\n")
  assert_decision_public_state_pure(underline, () => {
    match decide_block_quote_heading_continuation(underline) {
      Stop => ()
      _ => abort("expected block-quote setext Stop for underline")
    }
  })

  let thematic_underline = continuation_context_at_newline("para\n> ---\n")
  assert_decision_public_state_pure(thematic_underline, () => {
    match decide_block_quote_heading_continuation(thematic_underline) {
      Stop => ()
      _ => abort("expected block-quote setext Stop for thematic underline")
    }
  })
}

///|
test "continuation decisions: list-item variants" {
  let no_prefix = continuation_context_at_newline("para\nchild\n")
  assert_decision_public_state_pure(no_prefix, () => {
    match
      decide_list_item_continuation(
        no_prefix,
        2,
        allow_ordered_marker=true,
        has_paragraph_content=true,
      ) {
      Continue(ListItemContinuationKind::NoPrefix) => ()
      _ => abort("expected list-item NoPrefix")
    }
  })

  let indentation = continuation_context_at_newline("para\n  child\n")
  assert_decision_public_state_pure(indentation, () => {
    match
      decide_list_item_continuation(
        indentation,
        2,
        allow_ordered_marker=true,
        has_paragraph_content=true,
      ) {
      Continue(ListItemContinuationKind::IndentationPrefix) => ()
      _ => abort("expected list-item IndentationPrefix")
    }
  })

  let ordered = continuation_context_at_newline("para\n2. child\n")
  assert_decision_public_state_pure(ordered, () => {
    match
      decide_list_item_continuation(
        ordered,
        2,
        allow_ordered_marker=true,
        has_paragraph_content=true,
      ) {
      Continue(ListItemContinuationKind::OrderedMarkerAsText) => ()
      _ => abort("expected list-item OrderedMarkerAsText")
    }
  })
}

///|
test "continuation decisions: list-item Stop" {
  let no_paragraph = continuation_context_at_newline("para\nchild\n")
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

  let boundary = continuation_context_at_newline("para\n# heading\n")
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
  let no_prefix = continuation_context_at_newline("para\nchild\n")
  assert_decision_public_state_pure(no_prefix, () => {
    match
      decide_list_item_setext_continuation(
        no_prefix,
        2,
        allow_ordered_marker=true,
      ) {
      Continue(ListItemSetextContinuationKind::NoPrefix) => ()
      _ => abort("expected list-item setext NoPrefix")
    }
  })

  let indentation = continuation_context_at_newline("para\n  child\n")
  assert_decision_public_state_pure(indentation, () => {
    match
      decide_list_item_setext_continuation(
        indentation,
        2,
        allow_ordered_marker=true,
      ) {
      Continue(ListItemSetextContinuationKind::IndentationPrefix) => ()
      _ => abort("expected list-item setext IndentationPrefix")
    }
  })

  let ordered = continuation_context_at_newline("para\n2. child\n")
  assert_decision_public_state_pure(ordered, () => {
    match
      decide_list_item_setext_continuation(
        ordered,
        2,
        allow_ordered_marker=true,
      ) {
      Continue(ListItemSetextContinuationKind::OrderedMarkerAsText) => ()
      _ => abort("expected list-item setext OrderedMarkerAsText")
    }
  })
}

///|
test "continuation decisions: list-item setext Stop" {
  let underline = continuation_context_at_newline("para\n===\n")
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

  let boundary = continuation_context_at_newline("para\n# heading\n")
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
/// The pure fact walk records the typed action; only the actual parser pass
/// consumes it, so external counters observe exactly one consumption.
test "continuation driver: planned action consumes once" {
  let ctx = continuation_context("para\nchild\n")
  let consume_calls = [0]
  let no_prefix_calls = [0]
  let handler : ContinuationHandler[RootContinuationKind] = {
    decide: () => decide_root_paragraph_continuation(ctx),
    consume: action => {
      consume_calls[0] = consume_calls[0] + 1
      match action {
        RootContinuationKind::NoPrefix =>
          no_prefix_calls[0] = no_prefix_calls[0] + 1
        _ => abort("expected planned NoPrefix")
      }
      consume_root_continuation(ctx, action)
    },
    speculate: action => consume_root_continuation(ctx, action),
    observe: offset => observe_root_paragraph_continuation(ctx, offset),
    advance: (offset, action) => advance_root_continuation(ctx, offset, action),
  }
  parse_indexed_inline_container(ctx, InlineParsePolicy::paragraph(), handler)
  inspect(consume_calls[0], content="1")
  inspect(no_prefix_calls[0], content="1")
}

///|
test "continuation driver: unclosed multiline bold consumes once" {
  let ctx = continuation_context("**one\ntwo\n")
  let consume_calls = [0]
  let handler : ContinuationHandler[RootContinuationKind] = {
    decide: () => decide_root_paragraph_continuation(ctx),
    consume: action => {
      consume_calls[0] = consume_calls[0] + 1
      consume_root_continuation(ctx, action)
    },
    speculate: action => consume_root_continuation(ctx, action),
    observe: offset => observe_root_paragraph_continuation(ctx, offset),
    advance: (offset, action) => advance_root_continuation(ctx, offset, action),
  }
  parse_indexed_inline_container(ctx, InlineParsePolicy::paragraph(), handler)
  inspect(consume_calls[0], content="1")
}

///|
test "continuation driver: outer link rollback consumes nested action once" {
  let ctx = continuation_context("[**one\ntwo**]\n")
  let consume_calls = [0]
  let handler : ContinuationHandler[RootContinuationKind] = {
    decide: () => decide_root_paragraph_continuation(ctx),
    consume: action => {
      consume_calls[0] = consume_calls[0] + 1
      consume_root_continuation(ctx, action)
    },
    speculate: action => consume_root_continuation(ctx, action),
    observe: offset => observe_root_paragraph_continuation(ctx, offset),
    advance: (offset, action) => advance_root_continuation(ctx, offset, action),
  }
  parse_indexed_inline_container(ctx, InlineParsePolicy::paragraph(), handler)
  inspect(consume_calls[0], content="1")
}
