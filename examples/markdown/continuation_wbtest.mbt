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
  decision : () -> Unit raise,
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
/// The fact-plan walk records the same typed continuation action the actual
/// inline pass consumes. External counters must observe the parser pass only:
/// planning has no external consume effects.
test "continuation driver: fact planning has no consume effects" {
  let ctx = continuation_context("para\nchild\n")
  let consume_calls = [0]
  let no_prefix_calls = [0]
  let handler : ContinuationHandler[RootContinuationKind] = {
    consume: action => {
      consume_calls[0] = consume_calls[0] + 1
      match action {
        RootContinuationKind::NoPrefix =>
          no_prefix_calls[0] = no_prefix_calls[0] + 1
        _ => abort("expected NoPrefix in both parser passes")
      }
      consume_root_continuation(ctx, action)
    },
    observe: offset => observe_root_paragraph_continuation(ctx, offset),
    advance: (offset, action) => {
      advance_root_paragraph_continuation(ctx, offset, action)
    },
  }
  parse_indexed_inline_container(ctx, InlineParsePolicy::paragraph(), handler)
  inspect(consume_calls[0], content="1")
  inspect(no_prefix_calls[0], content="1")
}

///|

///|
fn describe_continuation_prefix(prefix : ContinuationPrefixKind) -> String {
  match prefix {
    ContinuationPrefixKind::NoPrefix => "NoPrefix"
    ContinuationPrefixKind::ThematicBreakPrefix => "ThematicBreakPrefix"
    ContinuationPrefixKind::ListMarkerPrefix => "ListMarkerPrefix"
  }
}

///|
fn describe_root_continuation(
  decision : ContinuationDecision[RootContinuationKind],
) -> String {
  match decision {
    Continue(RootContinuationKind::NoPrefix) => "Continue(NoPrefix)"
    Continue(RootContinuationKind::ThematicBreakPrefix) =>
      "Continue(ThematicBreakPrefix)"
    Continue(RootContinuationKind::ListMarkerPrefix) =>
      "Continue(ListMarkerPrefix)"
    Stop => "Stop"
  }
}

///|
fn describe_setext_continuation(
  decision : ContinuationDecision[SetextContinuationKind],
) -> String {
  match decision {
    Continue(SetextContinuationKind::NoPrefix) => "Continue(NoPrefix)"
    Continue(SetextContinuationKind::OrderedMarkerAsText) =>
      "Continue(OrderedMarkerAsText)"
    Stop => "Stop"
  }
}

///|
fn describe_block_quote_continuation(
  decision : ContinuationDecision[BlockQuoteContinuationKind],
) -> String {
  match decision {
    Continue(BlockQuoteContinuationKind::MarkerAndPrefix(prefix)) =>
      "Continue(MarkerAndPrefix(" + describe_continuation_prefix(prefix) + "))"
    Continue(BlockQuoteContinuationKind::PrefixOnly(prefix)) =>
      "Continue(PrefixOnly(" + describe_continuation_prefix(prefix) + "))"
    Stop => "Stop"
  }
}

///|
fn describe_block_quote_heading_continuation(
  decision : ContinuationDecision[BlockQuoteHeadingContinuationKind],
) -> String {
  match decision {
    Continue(BlockQuoteHeadingContinuationKind::MarkerAndPrefix(prefix)) =>
      "Continue(MarkerAndPrefix(" + describe_continuation_prefix(prefix) + "))"
    Stop => "Stop"
  }
}

///|
fn describe_list_item_continuation(
  decision : ContinuationDecision[ListItemContinuationKind],
) -> String {
  match decision {
    Continue(ListItemContinuationKind::NoPrefix) => "Continue(NoPrefix)"
    Continue(ListItemContinuationKind::IndentationPrefix) =>
      "Continue(IndentationPrefix)"
    Continue(ListItemContinuationKind::OrderedMarkerAsText) =>
      "Continue(OrderedMarkerAsText)"
    Stop => "Stop"
  }
}

///|
fn describe_list_item_setext_continuation(
  decision : ContinuationDecision[ListItemSetextContinuationKind],
) -> String {
  match decision {
    Continue(ListItemSetextContinuationKind::NoPrefix) => "Continue(NoPrefix)"
    Continue(ListItemSetextContinuationKind::IndentationPrefix) =>
      "Continue(IndentationPrefix)"
    Continue(ListItemSetextContinuationKind::OrderedMarkerAsText) =>
      "Continue(OrderedMarkerAsText)"
    Stop => "Stop"
  }
}

///|
fn[T] assert_continuation_fact_parity(
  source : String,
  decide : (@core.ParserContext[Token, SyntaxKind]) -> ContinuationDecision[T],
  consume : (@core.ParserContext[Token, SyntaxKind], T) -> Unit,
  observe : (@core.ParserContext[Token, SyntaxKind], Int) -> ContinuationDecision[
    T,
  ],
  advance : (@core.ParserContext[Token, SyntaxKind], Int, T) -> Int,
  describe : (ContinuationDecision[T]) -> String,
) -> Unit raise {
  let expected_ctx = continuation_context_at_newline(source)
  let expected = decide(expected_ctx)
  let fact_ctx = continuation_context_at_newline(source)
  let offset = fact_ctx.current_token_range().start
  assert_decision_public_state_pure(fact_ctx, fn() raise {
    inspect(describe(observe(fact_ctx, offset)), content=describe(expected))
  })
  match (expected, observe(fact_ctx, offset)) {
    (Continue(expected_action), Continue(observed_action)) => {
      consume(expected_ctx, expected_action)
      let expected_end = expected_ctx.current_token_range().start
      assert_decision_public_state_pure(fact_ctx, fn() raise {
        inspect(
          advance(fact_ctx, offset, observed_action),
          content=expected_end.to_string(),
        )
      })
    }
    (Stop, Stop) => ()
    _ => abort("fact observer decision diverged from context decision")
  }
}

///|
fn assert_setext_marker_underline_depth(
  marker : String,
  suffix : String,
  expected : Int?,
) -> Unit raise {
  let ctx = continuation_context_at_newline("para\n" + marker + suffix)
  let offset = ctx.current_token_range().start
  let context_depth = setext_underline_depth_after_newline(
    ctx,
    allow_list_marker=true,
    min_indent=0,
  )
  let fact_depth = setext_underline_depth_after_newline_at(
    ctx,
    offset,
    allow_list_marker=true,
    min_indent=0,
  )
  match (expected, context_depth, fact_depth) {
    (Some(expected), Some(context), Some(fact)) => {
      inspect(context, content=expected.to_string())
      inspect(fact, content=expected.to_string())
    }
    (None, None, None) => ()
    _ => abort("setext list-marker underline depth mismatch")
  }
}

///|
test "continuation facts: setext list markers end at every allowed shape" {
  for suffix in ["\n", "\n\n", "", " \n", " \n\n", " "] {
    assert_setext_marker_underline_depth("-", suffix, Some(2))
    assert_setext_marker_underline_depth("*", suffix, None)
    assert_setext_marker_underline_depth("+", suffix, None)
  }
}

///|
test "continuation facts: root paragraph actions and Stop" {
  for source in ["para\nbar\n", "para\n    ---\n", "para\n2. x\n", "para\n\n"] {
    assert_continuation_fact_parity(
      source, decide_root_paragraph_continuation, consume_root_continuation, observe_root_paragraph_continuation,
      advance_root_paragraph_continuation, describe_root_continuation,
    )
  }
}

///|
test "continuation facts: setext actions and Stop" {
  for source in ["para\nbar\n", "para\n2. x\n", "para\n===\n"] {
    assert_continuation_fact_parity(
      source, decide_setext_continuation, consume_setext_continuation, observe_setext_continuation,
      advance_setext_continuation, describe_setext_continuation,
    )
  }
}

///|
test "continuation facts: block quote paragraph actions and Stop" {
  for
    source in [
      "para\n> bar\n", "para\n>    ---\n", "para\n>2. x\n", "para\nbar\n", "para\n    ---\n",
      "para\n2. x\n", "para\n---\n",
    ] {
    assert_continuation_fact_parity(
      source, decide_block_quote_paragraph_continuation, consume_block_quote_continuation,
      observe_block_quote_paragraph_continuation, advance_block_quote_paragraph_continuation,
      describe_block_quote_continuation,
    )
  }
}

///|
test "continuation facts: block quote setext actions and Stop" {
  for
    source in [
      "para\n> bar\n", "para\n>    ---\n", "para\n>2. x\n", "para\n> ===\n",
    ] {
    assert_continuation_fact_parity(
      source, decide_block_quote_heading_continuation, consume_block_quote_heading_continuation,
      observe_block_quote_heading_continuation, advance_block_quote_heading_continuation,
      describe_block_quote_heading_continuation,
    )
  }
}

///|
test "continuation facts: list item actions and Stop" {
  for
    source in [
      "para\nchild\n", "para\n  child\n", "para\n2. child\n", "para\n# heading\n",
    ] {
    assert_continuation_fact_parity(
      source,
      ctx => {
        decide_list_item_continuation(
          ctx,
          2,
          allow_ordered_marker=true,
          has_paragraph_content=true,
        )
      },
      consume_list_item_continuation,
      (ctx, offset) => {
        observe_list_item_continuation(
          ctx,
          offset,
          2,
          allow_ordered_marker=true,
          has_paragraph_content=true,
        )
      },
      advance_list_item_continuation,
      describe_list_item_continuation,
    )
  }
}

///|
test "continuation facts: list item setext actions and Stop" {
  for
    source in [
      "para\nchild\n", "para\n  child\n", "para\n2. child\n", "para\n===\n",
    ] {
    assert_continuation_fact_parity(
      source,
      ctx => {
        decide_list_item_setext_continuation(ctx, 2, allow_ordered_marker=true)
      },
      consume_list_item_setext_continuation,
      (ctx, offset) => {
        observe_list_item_setext_continuation(
          ctx,
          offset,
          2,
          allow_ordered_marker=true,
        )
      },
      advance_list_item_setext_continuation,
      describe_list_item_setext_continuation,
    )
  }
}
