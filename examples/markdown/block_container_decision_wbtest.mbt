///|
fn block_start_facts(
  current : BlockTokenFact,
  after_prefix? : BlockTokenFact = FactInline,
  current_indent? : Int = 0,
  prefixed? : Bool = false,
) -> BlockLineFacts {
  BlockStart(BlockStartFacts::{
    current,
    after_prefix,
    current_indent,
    prefixed,
  })
}

///|
fn root_continuation_facts(
  next? : BlockTokenFact = FactInline,
  at_newline? : Bool = true,
  setext_underline? : Bool = false,
  prefixed_block_start? : Bool = false,
  lone_list_marker? : Bool = false,
  next_breaks_paragraph? : Bool = false,
  over_indented_atx? : Bool = false,
  prefix? : ContinuationPrefixKind = NoPrefix,
) -> BlockLineFacts {
  RootContinuation(RootContinuationFacts::{
    next,
    at_newline,
    setext_underline,
    prefixed_block_start,
    lone_list_marker,
    next_breaks_paragraph,
    over_indented_atx,
    prefix,
  })
}

///|
fn block_quote_continuation_facts(
  marked_line_continues? : Bool = false,
  marked_prefix? : ContinuationPrefixKind = NoPrefix,
  unquoted_line_continues? : Bool = false,
  unquoted_prefix? : ContinuationPrefixKind = NoPrefix,
  at_newline? : Bool = true,
  setext_underline? : Bool = false,
  unquoted_thematic_break? : Bool = false,
) -> BlockLineFacts {
  BlockQuoteContinuation(BlockQuoteContinuationFacts::{
    at_newline,
    setext_underline,
    marked_line_continues,
    marked_prefix,
    unquoted_line_continues,
    unquoted_prefix,
    unquoted_thematic_break,
  })
}

///|
fn list_item_continuation_facts(
  next? : BlockTokenFact = FactInline,
  next_indent? : Int? = None,
  at_newline? : Bool = true,
  setext_underline? : Bool = false,
  prefix_is_marker_boundary? : Bool = false,
  prefixed_block_start? : Bool = false,
  next_can_continue? : Bool = true,
) -> BlockLineFacts {
  ListItemContinuation(ListItemContinuationFacts::{
    next,
    next_indent,
    at_newline,
    setext_underline,
    prefix_is_marker_boundary,
    prefixed_block_start,
    next_can_continue,
  })
}

///|
fn block_start_action_name(action : BlockStartAction) -> String {
  match action {
    StartThematicBreak(false) => "thematic-break"
    StartThematicBreak(true) => "thematic-break-prefixed"
    StartHeading(false) => "heading"
    StartHeading(true) => "heading-prefixed"
    StartUnorderedList => "unordered-list"
    StartOrderedList => "ordered-list"
    StartBlockQuote => "block-quote"
    StartCodeFence(false) => "code-fence"
    StartCodeFence(true) => "code-fence-prefixed"
    StartHtmlBlock(false) => "html-block"
    StartHtmlBlock(true) => "html-block-prefixed"
    StartReferenceDefinition => "reference-definition"
    StartIndentedCode => "indented-code"
    StartIndentedMarkerCode => "indented-marker-code"
    StartParagraph(false) => "paragraph"
    StartParagraph(true) => "paragraph-prefixed"
    StartMarkerParagraph => "paragraph"
    StartOverIndentedHtmlParagraph => "over-indented-html-paragraph"
    ConsumeBlankLine => "blank-line"
    ConsumeNewline => "newline"
    EndOfInput => "end"
    SetextUnderline => "setext-underline"
  }
}

///|
fn continuation_action_name(action : BlockContinuationAction) -> String {
  match action {
    ContinueNoPrefix => "no-prefix"
    ContinueIndentedStructuralPrefix => "indented-structural-prefix"
    ContinueListMarkerPrefix => "list-marker-prefix"
    ContinueIndentationPrefix => "indentation-prefix"
    ContinueOrderedMarkerAsText => "ordered-marker-as-text"
    ContinueQuoteMarker(prefix) =>
      "quote-marker-" +
      continuation_action_name(continuation_action_from_prefix(prefix))
    ContinueQuoteLazy(prefix) =>
      "quote-lazy-" +
      continuation_action_name(continuation_action_from_prefix(prefix))
  }
}

///|
fn transition_decision_name(transition : BlockTransition) -> String {
  match transition.decision {
    StartBlock(action) => "start-" + block_start_action_name(action)
    ContinueParagraph(action) => "continue-" + continuation_action_name(action)
    StopParagraph(Some(action)) => "stop-" + block_start_action_name(action)
    StopParagraph(None) => "stop-none"
    Decline => "decline"
  }
}

///|
fn assert_start_decision(
  state : BlockContainerState,
  facts : BlockLineFacts,
  expected : String,
) -> Unit raise {
  let first = decide_block_container(state, facts)
  let second = decide_block_container(state, facts)
  let name = transition_decision_name(first)
  inspect(name, content=expected)
  inspect(transition_decision_name(second), content=expected)
  inspect(first.next_state.paragraph_open, content="false")
  inspect(second.next_state.paragraph_open, content="false")
}

///|
fn assert_continuation_decision(
  state : BlockContainerState,
  facts : BlockLineFacts,
  expected : String,
  paragraph_open~ : Bool,
) -> Unit raise {
  let first = decide_block_container(state, facts)
  let second = decide_block_container(state, facts)
  inspect(transition_decision_name(first), content=expected)
  inspect(transition_decision_name(second), content=expected)
  inspect(first.next_state.paragraph_open, content=paragraph_open.to_string())
  inspect(second.next_state.paragraph_open, content=paragraph_open.to_string())
}

///|
test "block container core: root block-start table is deterministic" {
  let state = root_block_container_state(ParagraphMode, false)
  assert_start_decision(state, block_start_facts(FactHeading), "start-heading")
  assert_start_decision(
    state,
    block_start_facts(
      FactIndentation,
      after_prefix=FactHeading,
      current_indent=3,
      prefixed=true,
    ),
    "start-heading-prefixed",
  )
  assert_start_decision(
    state,
    block_start_facts(FactIndentation, current_indent=4, prefixed=true),
    "start-indented-code",
  )
  assert_start_decision(
    state,
    block_start_facts(FactUnorderedMarker, current_indent=2),
    "start-unordered-list",
  )
  assert_start_decision(
    state,
    block_start_facts(FactUnorderedMarker, current_indent=4),
    "start-indented-marker-code",
  )
  assert_start_decision(
    state,
    block_start_facts(
      FactIndentation,
      after_prefix=FactFence,
      current_indent=3,
      prefixed=true,
    ),
    "start-code-fence-prefixed",
  )
  assert_start_decision(
    state,
    block_start_facts(FactBlockQuoteMarker, current_indent=4),
    "start-paragraph",
  )
  assert_start_decision(
    state,
    block_start_facts(FactHtmlBlock, current_indent=4),
    "start-over-indented-html-paragraph",
  )
  assert_start_decision(
    state,
    block_start_facts(FactReferenceDefinition),
    "start-reference-definition",
  )
}

///|
test "block container core: root continuation table owns boundaries" {
  let state = root_block_container_state(ParagraphMode, true)
  assert_continuation_decision(
    state,
    root_continuation_facts(),
    "continue-no-prefix",
    paragraph_open=true,
  )
  assert_continuation_decision(
    state,
    root_continuation_facts(
      next=FactUnorderedMarker,
      lone_list_marker=true,
      next_breaks_paragraph=true,
      prefix=ListMarkerPrefix,
    ),
    "continue-list-marker-prefix",
    paragraph_open=true,
  )
  assert_continuation_decision(
    state,
    root_continuation_facts(next=FactBlank, next_breaks_paragraph=true),
    "stop-blank-line",
    paragraph_open=false,
  )
  assert_continuation_decision(
    state,
    root_continuation_facts(next=FactFence, next_breaks_paragraph=true),
    "stop-code-fence",
    paragraph_open=false,
  )
  assert_continuation_decision(
    state,
    root_continuation_facts(next=FactIndentation, over_indented_atx=true),
    "continue-indentation-prefix",
    paragraph_open=true,
  )
}

///|
test "block container core: blockquote explicit and lazy continuation table" {
  let state = block_quote_container_state(ParagraphMode)
  assert_continuation_decision(
    state,
    block_quote_continuation_facts(marked_line_continues=true),
    "continue-quote-marker-no-prefix",
    paragraph_open=true,
  )
  assert_continuation_decision(
    state,
    block_quote_continuation_facts(
      unquoted_line_continues=true,
      unquoted_prefix=ListMarkerPrefix,
    ),
    "continue-quote-lazy-list-marker-prefix",
    paragraph_open=true,
  )
  assert_continuation_decision(
    state,
    block_quote_continuation_facts(
      unquoted_line_continues=true,
      unquoted_thematic_break=true,
    ),
    "stop-thematic-break",
    paragraph_open=false,
  )
  assert_continuation_decision(
    state,
    block_quote_continuation_facts(),
    "stop-none",
    paragraph_open=false,
  )
}

///|
test "block container core: list-item continuation table owns boundaries" {
  let state = list_item_block_container_state(
    ParagraphMode,
    content_indent=2,
    allow_ordered_marker=true,
    paragraph_open=true,
  )
  assert_continuation_decision(
    state,
    list_item_continuation_facts(next=FactIndentation, next_indent=Some(2)),
    "continue-indentation-prefix",
    paragraph_open=true,
  )
  assert_continuation_decision(
    state,
    list_item_continuation_facts(next=FactOrderedMarker, next_indent=Some(0)),
    "continue-ordered-marker-as-text",
    paragraph_open=true,
  )
  assert_continuation_decision(
    state,
    list_item_continuation_facts(next=FactOrderedMarker, next_indent=Some(2)),
    "stop-ordered-list",
    paragraph_open=false,
  )
  assert_continuation_decision(
    state,
    list_item_continuation_facts(
      next=FactFence,
      next_can_continue=false,
      prefixed_block_start=true,
    ),
    "stop-code-fence",
    paragraph_open=false,
  )
  let empty = list_item_block_container_state(
    ParagraphMode,
    content_indent=2,
    allow_ordered_marker=true,
    paragraph_open=false,
  )
  assert_continuation_decision(
    empty,
    list_item_continuation_facts(),
    "stop-none",
    paragraph_open=false,
  )
}

///|
test "block container core: closing a setext candidate resets transient state" {
  let state = root_block_container_state(SetextMode, true)
  let transition = decide_block_container(
    state,
    root_continuation_facts(setext_underline=true),
  )
  inspect(transition_decision_name(transition), content="stop-setext-underline")
  inspect(transition.next_state.paragraph_open, content="false")
  match transition.next_state.mode {
    ParagraphMode => ()
    SetextMode => abort("closed setext state must return to paragraph mode")
  }
}

///|
test "block container core: mismatched facts decline without mutating state" {
  let state = block_quote_container_state(ParagraphMode)
  let transition = decide_block_container(state, root_continuation_facts())
  inspect(transition_decision_name(transition), content="decline")
  inspect(transition.next_state.paragraph_open, content="true")
  match transition.next_state.frame {
    BlockQuoteFrame => ()
    _ => abort("decline must retain the current frame")
  }
}
