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
test "continuation decisions: root variants" {
  let no_prefix = continuation_context("\nbar\n")
  assert_decision_public_state_pure(no_prefix, () => {
    match decide_root_paragraph_continuation(no_prefix) {
      Continue(RootContinuationKind::NoPrefix) => ()
      _ => abort("expected root NoPrefix")
    }
  })

  // Indented thematic-break-looking line (indent >= 4) continues as text.
  // Bare "\n---\n" / "\n ---\n" stop via prefix dispatch or block boundary.
  let thematic = continuation_context("\n    ---\n")
  assert_decision_public_state_pure(thematic, () => {
    match decide_root_paragraph_continuation(thematic) {
      Continue(ThematicBreakPrefix) => ()
      _ => abort("expected root ThematicBreakPrefix")
    }
  })

  // Lone list marker continues as text; "\n- item\n" interrupts as a list.
  let list_marker = continuation_context("\n-\n")
  assert_decision_public_state_pure(list_marker, () => {
    match decide_root_paragraph_continuation(list_marker) {
      Continue(ListMarkerPrefix) => ()
      _ => abort("expected root ListMarkerPrefix")
    }
  })

  // Ordered markers with start != 1 are ListMarkerPrefix continuations.
  let ordered = continuation_context("\n2. x\n")
  assert_decision_public_state_pure(ordered, () => {
    match decide_root_paragraph_continuation(ordered) {
      Continue(ListMarkerPrefix) => ()
      _ => abort("expected root ListMarkerPrefix for non-1 ordered marker")
    }
  })
}

///|
test "continuation decisions: root Stop" {
  let blank = continuation_context("\n\n")
  assert_decision_public_state_pure(blank, () => {
    match decide_root_paragraph_continuation(blank) {
      Stop => ()
      _ => abort("expected root Stop for blank line")
    }
  })

  let thematic = continuation_context("\n---\n")
  assert_decision_public_state_pure(thematic, () => {
    match decide_root_paragraph_continuation(thematic) {
      Stop => ()
      _ => abort("expected root Stop for bare thematic break")
    }
  })

  let list_item = continuation_context("\n- item\n")
  assert_decision_public_state_pure(list_item, () => {
    match decide_root_paragraph_continuation(list_item) {
      Stop => ()
      _ => abort("expected root Stop for list item")
    }
  })

  let ordered_one = continuation_context("\n1. x\n")
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
