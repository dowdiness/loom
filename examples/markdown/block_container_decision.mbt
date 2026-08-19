///|
/// Private Markdown-local container frame. The parser shell observes tokens;
/// this value records only the CommonMark context needed by pure decisions.
priv enum BlockContainerFrame {
  RootFrame
  BlockQuoteFrame
  ListItemFrame(Int, Bool)
}

///|
priv enum BlockContinuationMode {
  ParagraphMode
  SetextMode
}

///|
priv struct BlockContainerState {
  frame : BlockContainerFrame
  mode : BlockContinuationMode
  paragraph_open : Bool
}

///|
fn root_block_container_state(
  mode : BlockContinuationMode,
  paragraph_open : Bool,
) -> BlockContainerState {
  { frame: RootFrame, mode, paragraph_open }
}

///|
fn block_quote_container_state(
  mode : BlockContinuationMode,
) -> BlockContainerState {
  { frame: BlockQuoteFrame, mode, paragraph_open: true }
}

///|
fn list_item_block_container_state(
  mode : BlockContinuationMode,
  content_indent~ : Int,
  allow_ordered_marker~ : Bool,
  paragraph_open~ : Bool,
) -> BlockContainerState {
  {
    frame: ListItemFrame(content_indent, allow_ordered_marker),
    mode,
    paragraph_open,
  }
}

///|
/// Token-level facts are deliberately smaller than Markdown tokens. The shell
/// classifies without consuming; the core never reads ParserContext.
priv enum BlockTokenFact {
  FactThematicBreak
  FactHeading
  FactUnorderedMarker
  FactOrderedMarker
  FactBlockQuoteMarker
  FactFence
  FactHtmlBlock
  FactReferenceDefinition
  FactBlank
  FactIndentation
  FactNewline
  FactEnd
  FactInline
}

///|
priv enum ContinuationPrefixKind {
  NoPrefix
  ThematicBreakPrefix
  ListMarkerPrefix
}

///|
priv struct BlockStartFacts {
  current : BlockTokenFact
  after_prefix : BlockTokenFact
  current_indent : Int
  prefixed : Bool
}

///|
priv struct RootContinuationFacts {
  next : BlockTokenFact
  at_newline : Bool
  setext_underline : Bool
  prefixed_block_start : Bool
  lone_list_marker : Bool
  next_breaks_paragraph : Bool
  over_indented_atx : Bool
  prefix : ContinuationPrefixKind
}

///|
priv struct BlockQuoteContinuationFacts {
  at_newline : Bool
  setext_underline : Bool
  marked_line_continues : Bool
  marked_prefix : ContinuationPrefixKind
  unquoted_line_continues : Bool
  unquoted_prefix : ContinuationPrefixKind
  unquoted_thematic_break : Bool
}

///|
priv struct ListItemContinuationFacts {
  next : BlockTokenFact
  next_indent : Int?
  at_newline : Bool
  setext_underline : Bool
  prefix_is_marker_boundary : Bool
  prefixed_block_start : Bool
  next_can_continue : Bool
}

///|
priv enum BlockLineFacts {
  BlockStart(BlockStartFacts)
  RootContinuation(RootContinuationFacts)
  BlockQuoteContinuation(BlockQuoteContinuationFacts)
  ListItemContinuation(ListItemContinuationFacts)
}

///|
/// Typed shell actions preserve the current parser dispatch exactly.
priv enum BlockStartAction {
  StartThematicBreak(Bool)
  StartHeading(Bool)
  StartUnorderedList
  StartOrderedList
  StartBlockQuote
  StartCodeFence(Bool)
  StartHtmlBlock(Bool)
  StartReferenceDefinition
  StartIndentedCode
  StartIndentedMarkerCode
  StartParagraph(Bool)
  StartMarkerParagraph
  StartOverIndentedHtmlParagraph
  ConsumeBlankLine
  ConsumeNewline
  EndOfInput
  SetextUnderline
}

///|
priv enum BlockContinuationAction {
  ContinueNoPrefix
  ContinueThematicBreakPrefix
  ContinueListMarkerPrefix
  ContinueIndentationPrefix
  ContinueOrderedMarkerAsText
  ContinueQuoteMarker(ContinuationPrefixKind)
  ContinueQuoteLazy(ContinuationPrefixKind)
}

///|
priv enum BlockDecision {
  StartBlock(BlockStartAction)
  ContinueParagraph(BlockContinuationAction)
  StopParagraph(BlockStartAction?)
  Decline
}

///|
priv struct BlockTransition {
  next_state : BlockContainerState
  decision : BlockDecision
}

///|
fn block_state_with_paragraph(
  state : BlockContainerState,
  paragraph_open : Bool,
) -> BlockContainerState {
  { frame: state.frame, mode: state.mode, paragraph_open }
}

///|
fn start_transition(
  state : BlockContainerState,
  action : BlockStartAction,
) -> BlockTransition {
  {
    next_state: block_state_with_paragraph(state, false),
    decision: StartBlock(action),
  }
}

///|
fn continue_transition(
  state : BlockContainerState,
  action : BlockContinuationAction,
) -> BlockTransition {
  {
    next_state: block_state_with_paragraph(state, true),
    decision: ContinueParagraph(action),
  }
}

///|
fn stop_paragraph_transition(
  state : BlockContainerState,
  next : BlockStartAction?,
) -> BlockTransition {
  {
    next_state: {
      frame: state.frame,
      mode: ParagraphMode,
      paragraph_open: false,
    },
    decision: StopParagraph(next),
  }
}

///|
fn decline_transition(state : BlockContainerState) -> BlockTransition {
  { next_state: state, decision: Decline }
}

///|
fn continuation_action_from_prefix(
  prefix : ContinuationPrefixKind,
) -> BlockContinuationAction {
  match prefix {
    NoPrefix => ContinueNoPrefix
    ThematicBreakPrefix => ContinueThematicBreakPrefix
    ListMarkerPrefix => ContinueListMarkerPrefix
  }
}

///|
fn block_start_from_token_fact(fact : BlockTokenFact) -> BlockStartAction? {
  match fact {
    FactThematicBreak => Some(StartThematicBreak(false))
    FactHeading => Some(StartHeading(false))
    FactUnorderedMarker => Some(StartUnorderedList)
    FactOrderedMarker => Some(StartOrderedList)
    FactBlockQuoteMarker => Some(StartBlockQuote)
    FactFence => Some(StartCodeFence(false))
    FactHtmlBlock => Some(StartHtmlBlock(false))
    FactReferenceDefinition => Some(StartReferenceDefinition)
    FactBlank => Some(ConsumeBlankLine)
    FactNewline => Some(ConsumeNewline)
    FactEnd => Some(EndOfInput)
    FactIndentation | FactInline => None
  }
}

///|
fn decide_root_block_start(
  state : BlockContainerState,
  facts : BlockStartFacts,
) -> BlockTransition {
  let action = match facts.current {
    FactThematicBreak => StartThematicBreak(facts.prefixed)
    FactHeading => StartHeading(facts.prefixed)
    FactUnorderedMarker =>
      if facts.current_indent >= 0 && facts.current_indent <= 3 {
        StartUnorderedList
      } else if facts.current_indent >= 4 {
        StartIndentedMarkerCode
      } else {
        StartMarkerParagraph
      }
    FactOrderedMarker =>
      if facts.current_indent >= 0 && facts.current_indent <= 3 {
        StartOrderedList
      } else if facts.current_indent >= 4 {
        StartIndentedMarkerCode
      } else {
        StartMarkerParagraph
      }
    FactBlockQuoteMarker =>
      if facts.current_indent <= 3 {
        StartBlockQuote
      } else {
        StartMarkerParagraph
      }
    FactFence => StartCodeFence(facts.prefixed)
    FactHtmlBlock =>
      if facts.current_indent <= 3 {
        StartHtmlBlock(facts.prefixed)
      } else {
        StartOverIndentedHtmlParagraph
      }
    FactReferenceDefinition => StartReferenceDefinition
    FactBlank => ConsumeBlankLine
    FactIndentation =>
      if facts.current_indent >= 4 {
        StartIndentedCode
      } else {
        match facts.after_prefix {
          FactThematicBreak => StartThematicBreak(true)
          FactHeading => StartHeading(true)
          FactUnorderedMarker => StartUnorderedList
          FactOrderedMarker => StartOrderedList
          FactBlockQuoteMarker => StartBlockQuote
          FactFence => StartCodeFence(true)
          FactHtmlBlock => StartHtmlBlock(true)
          FactReferenceDefinition => StartReferenceDefinition
          _ => StartParagraph(true)
        }
      }
    FactNewline => ConsumeNewline
    FactEnd => EndOfInput
    FactInline => StartParagraph(false)
  }
  start_transition(state, action)
}

///|
fn decide_root_continuation(
  state : BlockContainerState,
  facts : RootContinuationFacts,
) -> BlockTransition {
  if !facts.at_newline {
    stop_paragraph_transition(state, None)
  } else if state.mode is SetextMode && facts.setext_underline {
    stop_paragraph_transition(state, Some(SetextUnderline))
  } else if facts.prefixed_block_start ||
    (
      !facts.lone_list_marker &&
      (
        facts.next_breaks_paragraph ||
        facts.next is FactNewline ||
        facts.next is FactEnd
      )
    ) {
    stop_paragraph_transition(state, block_start_from_token_fact(facts.next))
  } else if state.mode is SetextMode && facts.next is FactOrderedMarker {
    continue_transition(state, ContinueOrderedMarkerAsText)
  } else if facts.over_indented_atx {
    continue_transition(state, ContinueIndentationPrefix)
  } else {
    continue_transition(state, continuation_action_from_prefix(facts.prefix))
  }
}

///|
fn decide_block_quote_continuation_core(
  state : BlockContainerState,
  facts : BlockQuoteContinuationFacts,
) -> BlockTransition {
  if !facts.at_newline {
    stop_paragraph_transition(state, None)
  } else if state.mode is SetextMode && facts.setext_underline {
    stop_paragraph_transition(state, Some(SetextUnderline))
  } else if facts.marked_line_continues {
    continue_transition(state, ContinueQuoteMarker(facts.marked_prefix))
  } else if state.mode is ParagraphMode &&
    facts.unquoted_line_continues &&
    !facts.unquoted_thematic_break {
    continue_transition(state, ContinueQuoteLazy(facts.unquoted_prefix))
  } else if facts.unquoted_thematic_break {
    stop_paragraph_transition(state, Some(StartThematicBreak(false)))
  } else {
    stop_paragraph_transition(state, None)
  }
}

///|
fn decide_list_item_continuation_core(
  state : BlockContainerState,
  content_indent : Int,
  allow_ordered_marker : Bool,
  facts : ListItemContinuationFacts,
) -> BlockTransition {
  if !state.paragraph_open || !facts.at_newline {
    stop_paragraph_transition(state, None)
  } else if state.mode is SetextMode && facts.setext_underline {
    stop_paragraph_transition(state, Some(SetextUnderline))
  } else if allow_ordered_marker &&
    facts.next is FactOrderedMarker &&
    facts.next_indent.map_or(false, indent => indent >= content_indent) {
    stop_paragraph_transition(state, Some(StartOrderedList))
  } else if facts.prefix_is_marker_boundary ||
    facts.prefixed_block_start ||
    !facts.next_can_continue {
    stop_paragraph_transition(state, block_start_from_token_fact(facts.next))
  } else {
    let action = match facts.next {
      FactIndentation => ContinueIndentationPrefix
      FactOrderedMarker if allow_ordered_marker => ContinueOrderedMarkerAsText
      _ => ContinueNoPrefix
    }
    continue_transition(state, action)
  }
}

///|
/// Deterministic Functional Core. ParserContext lookahead and all effects stay
/// in cst_parser.mbt; mismatched fact/state pairs decline conservatively.
fn decide_block_container(
  state : BlockContainerState,
  facts : BlockLineFacts,
) -> BlockTransition {
  match (state.frame, facts) {
    (RootFrame, BlockStart(start)) => decide_root_block_start(state, start)
    (RootFrame, RootContinuation(line)) => decide_root_continuation(state, line)
    (BlockQuoteFrame, BlockQuoteContinuation(line)) =>
      decide_block_quote_continuation_core(state, line)
    (
      ListItemFrame(content_indent, allow_ordered_marker),
      ListItemContinuation(line),
    ) =>
      decide_list_item_continuation_core(
        state, content_indent, allow_ordered_marker, line,
      )
    _ => decline_transition(state)
  }
}
