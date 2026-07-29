// Inline parser for Markdown.
//
// Markdown delimiters (*, _, `, [) are ambiguous. One container-local analysis
// indexes code spans and confirmed links, then builds the emphasis plan. The
// parser emits that plan without speculative inline rescans, keeping matching
// linear while preserving literal source spelling for unmatched runs.

///|
/// True when the current token ends an inline run: block markers, newlines,
/// blank lines, or EOF. Inline parsers check this to know when to stop.
fn is_inline_end(token : Token) -> Bool {
  is_block_boundary(token) || token is Newline || token == EOF
}

///|
fn token_is_inline_block_boundary(
  token : Token,
  policy : InlineParsePolicy,
) -> Bool {
  match token {
    OrderedListMarker(_) if policy.allows_ordered_marker() =>
      token_breaks_paragraph_after_newline(token)
    _ => is_block_boundary(token)
  }
}

///|
fn token_is_inline_end(token : Token, policy : InlineParsePolicy) -> Bool {
  token_is_inline_block_boundary(token, policy) || token is Newline
}

///|
priv struct CodeSpanDelimiterIndex {
  eligible_openers : Map[Int, Bool]
  successors : Map[Int, Int]
}

///|
priv struct InlineDelimiterPlanCursor {
  events : ReadOnlyArray[DelimiterPlanEvent]
  mut event_index : Int
  emphasis_stack : Array[ResolvedEmphasisKind]
}

///|
fn delimiter_neighbor_from_char(ch : Char?) -> DelimiterNeighbor {
  match ch {
    None => DelimiterWhitespace
    Some(ch) if is_commonmark_unicode_whitespace(ch) => DelimiterWhitespace
    Some(ch) if is_unicode_punctuation_or_symbol(ch) =>
      DelimiterPunctuationOrSymbol
    Some(_) => DelimiterOther
  }
}

///|
fn first_char_in_inline_text(text : StringView) -> Char? {
  for ch in text {
    return Some(ch)
  }
  None
}

///|
fn last_char_in_inline_text(text : StringView) -> Char? {
  let mut last = None
  for ch in text {
    last = Some(ch)
  }
  last
}

///|
priv enum InlineAnalysisTokenKind {
  AnalysisAsterisk
  AnalysisUnderscore
  AnalysisBacktick
  AnalysisLeftBracket
  AnalysisRightBracket
  AnalysisLeftParen
  AnalysisRightParen
  AnalysisLineBoundary
  AnalysisOther
} derive(Eq)

///|
priv struct InlineAnalysisToken {
  kind : InlineAnalysisTokenKind
  start : Int
  end : Int
  first : Char?
  last : Char?
  ends_with_odd_backslashes : Bool
}

///|
priv struct InlineLinkDelimiterIndex {
  label_closers_by_open : Map[Int, Int]
  label_closes : Map[Int, Bool]
  destination_ends : Map[Int, Int]
}

///|
fn inline_analysis_token_kind(token : Token) -> InlineAnalysisTokenKind {
  match token {
    Star => AnalysisAsterisk
    Underscore => AnalysisUnderscore
    Backtick => AnalysisBacktick
    LeftBracket => AnalysisLeftBracket
    RightBracket => AnalysisRightBracket
    LeftParen => AnalysisLeftParen
    RightParen => AnalysisRightParen
    _ => AnalysisOther
  }
}

///|
fn collect_inline_analysis_tokens(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  continue_line : () -> Bool,
) -> Array[InlineAnalysisToken] {
  let tokens : Array[InlineAnalysisToken] = []
  while true {
    while !token_is_inline_end(ctx.peek(), policy) {
      let range = ctx.current_token_range()
      let text = ctx.current_token_text()
      tokens.push({
        kind: inline_analysis_token_kind(ctx.peek()),
        start: range.start,
        end: range.end,
        first: first_char_in_inline_text(text),
        last: last_char_in_inline_text(text),
        ends_with_odd_backslashes: ctx.peek() is Text(_) &&
        text_ends_with_odd_backslashes(text),
      })
      ctx.emit_current_token()
    }
    if ctx.peek() is Newline {
      let boundary_start = ctx.current_token_range().start
      if continue_line() {
        let next_start = ctx.current_token_range().start
        tokens.push({
          kind: AnalysisLineBoundary,
          start: boundary_start,
          end: next_start,
          first: Some('\n'),
          last: Some('\n'),
          ends_with_odd_backslashes: false,
        })
      } else {
        break
      }
    } else {
      break
    }
  }
  tokens
}

///|
fn analysis_code_closer_index(
  tokens : Array[InlineAnalysisToken],
  index : Int,
  code_delimiters : CodeSpanDelimiterIndex,
) -> Int? {
  let token = tokens[index]
  guard token.kind == AnalysisBacktick &&
    code_delimiters.eligible_openers.get(token.start).unwrap_or(false) &&
    code_delimiters.successors.get(token.start) is Some(closer_start) else {
    return None
  }
  for i = index + 1; i < tokens.length(); i = i + 1 {
    if tokens[i].start == closer_start {
      return Some(i)
    }
  }
  abort("code delimiter index points outside its inline container")
}

///|
fn clear_analysis_stack(stack : Array[Int]) -> Unit {
  while stack.pop() is Some(_) {
    ()
  }
}

///|
fn index_inline_links(
  tokens : Array[InlineAnalysisToken],
  code_delimiters : CodeSpanDelimiterIndex,
) -> InlineLinkDelimiterIndex {
  let paren_matches : Map[Int, Int] = Map([])
  let paren_stack : Array[Int] = []
  let mut index = 0
  while index < tokens.length() {
    // Backticks have no code-span semantics inside a link destination, so
    // every parenthesis participates in the same balance that parse_link
    // consumes below. Code spans remain opaque only while matching labels.
    match tokens[index].kind {
      AnalysisLineBoundary => clear_analysis_stack(paren_stack)
      AnalysisLeftParen => paren_stack.push(index)
      AnalysisRightParen =>
        match paren_stack.pop() {
          Some(opener) => paren_matches[opener] = index
          None => ()
        }
      _ => ()
    }
    index = index + 1
  }
  let links : InlineLinkDelimiterIndex = {
    label_closers_by_open: Map([]),
    label_closes: Map([]),
    destination_ends: Map([]),
  }
  let bracket_stack : Array[Int] = []
  index = 0
  while index < tokens.length() {
    match analysis_code_closer_index(tokens, index, code_delimiters) {
      Some(closer) => index = closer + 1
      None => {
        match tokens[index].kind {
          AnalysisLeftBracket => bracket_stack.push(index)
          AnalysisRightBracket =>
            match bracket_stack.pop() {
              Some(opener) => {
                let destination_start = index + 1
                if destination_start < tokens.length() &&
                  tokens[destination_start].kind == AnalysisLeftParen &&
                  paren_matches.get(destination_start) is Some(destination_end) {
                  links.label_closers_by_open[tokens[opener].start] = tokens[index].start
                  links.label_closes[tokens[index].start] = true
                  links.destination_ends[tokens[destination_start].start] = tokens[destination_end].end
                  index = destination_end
                }
              }
              None => ()
            }
          _ => ()
        }
        index = index + 1
      }
    }
  }
  links
}

///|
fn analysis_delimiter_marker(
  kind : InlineAnalysisTokenKind,
) -> EmphasisDelimiterMarker? {
  match kind {
    AnalysisAsterisk => Some(AsteriskDelimiter)
    AnalysisUnderscore => Some(UnderscoreDelimiter)
    _ => None
  }
}

///|
fn build_inline_delimiter_plan(
  tokens : Array[InlineAnalysisToken],
  code_delimiters : CodeSpanDelimiterIndex,
  links : InlineLinkDelimiterIndex,
) -> DelimiterResolutionPlan {
  let events : Array[DelimiterResolverEvent] = []
  let mut previous_char : Char? = None
  let mut index = 0
  while index < tokens.length() {
    match analysis_code_closer_index(tokens, index, code_delimiters) {
      Some(closer) => {
        events.push(
          OpaqueInlineEvent(
            DelimiterSourceRange(tokens[index].start, tokens[closer].end),
          ),
        )
        previous_char = Some('`')
        index = closer + 1
      }
      None =>
        match links.destination_ends.get(tokens[index].start) {
          Some(destination_end) => {
            let start = tokens[index].start
            while index < tokens.length() && tokens[index].end < destination_end {
              index = index + 1
            }
            guard index < tokens.length() &&
              tokens[index].end == destination_end else {
              abort(
                "link destination index points outside its inline container",
              )
            }
            events.push(
              OpaqueInlineEvent(DelimiterSourceRange(start, destination_end)),
            )
            previous_char = Some(')')
            index = index + 1
          }
          None => {
            if links.label_closers_by_open.get(tokens[index].start) is Some(_) {
              events.push(PushLinkLabelScope)
            }
            match analysis_delimiter_marker(tokens[index].kind) {
              Some(marker) => {
                let start = tokens[index].start
                let mut end = tokens[index].end
                let mut next = index + 1
                while next < tokens.length() &&
                      analysis_delimiter_marker(tokens[next].kind) ==
                      Some(marker) &&
                      tokens[next].start == end {
                  end = tokens[next].end
                  next = next + 1
                }
                let after = if next < tokens.length() {
                  tokens[next].first
                } else {
                  None
                }
                events.push(
                  DelimiterRunEvent(
                    delimiter_run_fact(
                      marker,
                      start,
                      end - start,
                      delimiter_neighbor_from_char(previous_char),
                      delimiter_neighbor_from_char(after),
                      escaped=false,
                    ),
                  ),
                )
                previous_char = if marker is AsteriskDelimiter {
                  Some('*')
                } else {
                  Some('_')
                }
                index = next
              }
              None => {
                previous_char = tokens[index].last
                if links.label_closes.get(tokens[index].start).unwrap_or(false) {
                  events.push(ResolveLinkLabelScope)
                }
                index = index + 1
              }
            }
          }
        }
    }
  }
  resolve_delimiter_events(events)
}

///|
fn delimiter_event_range(event : DelimiterPlanEvent) -> DelimiterSourceRange {
  match event {
    OpenEmphasisDelimiter(_, range)
    | CloseEmphasisDelimiter(_, range)
    | LiteralEmphasisDelimiter(_, range) => range
  }
}

///|
fn delimiter_token_matches_marker(
  token : Token,
  marker : EmphasisDelimiterMarker,
) -> Bool {
  match (token, marker) {
    (Star, AsteriskDelimiter) | (Underscore, UnderscoreDelimiter) => true
    _ => false
  }
}

///|
fn emit_planned_delimiter_range(
  ctx : @core.ParserContext[Token, SyntaxKind],
  range : DelimiterSourceRange,
  kind : SyntaxKind,
  marker : EmphasisDelimiterMarker?,
) -> Unit {
  let DelimiterSourceRange(start, end) = range
  let mut offset = start
  let mut inferred_marker : EmphasisDelimiterMarker? = marker
  while offset < end {
    let current = ctx.current_token_range()
    guard current.start == offset && current.length() == 1 else {
      abort("delimiter plan range must align with one-character lexer facts")
    }
    let current_marker = match ctx.peek() {
      Star => AsteriskDelimiter
      Underscore => UnderscoreDelimiter
      _ => abort("delimiter plan range must point at a delimiter token")
    }
    match inferred_marker {
      Some(expected) => {
        guard delimiter_token_matches_marker(ctx.peek(), expected) else {
          abort("delimiter plan marker does not match the lexer token")
        }
      }
      None => inferred_marker = Some(current_marker)
    }
    ctx.emit_token(kind)
    offset = current.end
  }
  guard offset == end else {
    abort("delimiter plan range must end on a lexer token boundary")
  }
}

///|
fn try_emit_planned_delimiter(
  ctx : @core.ParserContext[Token, SyntaxKind],
  cursor : InlineDelimiterPlanCursor,
) -> Bool {
  guard cursor.event_index < cursor.events.length() else { return false }
  let event = cursor.events[cursor.event_index]
  let DelimiterSourceRange(start, _) = delimiter_event_range(event)
  guard delimiter_event_is_ready(
    current_start=ctx.current_token_range().start,
    event_start=start,
  ) else {
    return false
  }
  match event {
    OpenEmphasisDelimiter(kind, range) => {
      cursor.emphasis_stack.push(kind)
      ctx.start_node(
        match kind {
          ResolvedEmphasis => ItalicNode
          ResolvedStrong => BoldNode
        },
      )
      emit_planned_delimiter_range(ctx, range, EmphasisDelimiterToken, None)
    }
    CloseEmphasisDelimiter(kind, range) => {
      emit_planned_delimiter_range(ctx, range, EmphasisDelimiterToken, None)
      guard cursor.emphasis_stack.pop() is Some(open_kind) && open_kind == kind else {
        abort("delimiter plan emitted an unbalanced emphasis close")
      }
      ctx.finish_node()
    }
    LiteralEmphasisDelimiter(marker, range) =>
      emit_planned_delimiter_range(ctx, range, TextToken, Some(marker))
  }
  cursor.event_index = cursor.event_index + 1
  true
}

///|
fn delimiter_event_is_ready(current_start~ : Int, event_start~ : Int) -> Bool {
  guard event_start >= current_start else {
    abort("delimiter plan event was skipped by parser emission")
  }
  event_start == current_start
}

///|
fn validate_delimiter_cursor_completion(
  event_index~ : Int,
  event_count~ : Int,
  emphasis_depth~ : Int,
) -> Unit {
  guard event_index == event_count else {
    abort("inline container ended with unconsumed delimiter plan events")
  }
  guard emphasis_depth == 0 else {
    abort("inline container ended with unclosed emphasis nodes")
  }
}

///|
fn text_ends_with_odd_backslashes(text : StringView) -> Bool {
  let mut count = 0
  for ch in text {
    if ch == '\\' {
      count = count + 1
    } else {
      count = 0
    }
  }
  count % 2 == 1
}

///|
fn index_code_span_delimiter_run(
  index : CodeSpanDelimiterIndex,
  previous_by_length : Map[Int, Int],
  start : Int,
  run_length : Int,
  eligible_opener : Bool,
) -> Unit {
  index.eligible_openers[start] = eligible_opener
  match previous_by_length.get(run_length) {
    Some(previous) => index.successors[previous] = start
    None => ()
  }
  previous_by_length[run_length] = start
}

///|
fn build_code_span_delimiter_index(
  tokens : Array[InlineAnalysisToken],
) -> CodeSpanDelimiterIndex {
  let index : CodeSpanDelimiterIndex = {
    eligible_openers: Map([]),
    successors: Map([]),
  }
  let previous_by_length : Map[Int, Int] = Map([])
  let mut preceding_text_ends_escaped = false
  for token in tokens {
    if token.kind == AnalysisBacktick {
      index_code_span_delimiter_run(
        index,
        previous_by_length,
        token.start,
        token.end - token.start,
        !preceding_text_ends_escaped,
      )
      preceding_text_ends_escaped = false
    } else {
      preceding_text_ends_escaped = token.ends_with_odd_backslashes
    }
  }
  index
}

///|
priv enum ContinuationDecision[T] {
  Continue(T)
  Stop
}

///|
priv struct ContinuationHandler[T] {
  decide : () -> ContinuationDecision[T]
  consume : (T) -> Unit
}

///|
fn[T] continuation_step(handler : ContinuationHandler[T]) -> () -> Bool {
  () => {
    match (handler.decide)() {
      Continue(action) => {
        (handler.consume)(action)
        true
      }
      Stop => false
    }
  }
}

///|
fn parse_indexed_inline_container_with_continue_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  continue_line : () -> Bool,
) -> Unit {
  let analysis_tokens = ctx.lookahead(() => {
    collect_inline_analysis_tokens(ctx, policy, continue_line)
  })
  let delimiters = build_code_span_delimiter_index(analysis_tokens)
  let links = index_inline_links(analysis_tokens, delimiters)
  let delimiter_plan = build_inline_delimiter_plan(
    analysis_tokens, delimiters, links,
  )
  let delimiter_cursor : InlineDelimiterPlanCursor = {
    events: delimiter_plan.events,
    event_index: 0,
    emphasis_stack: [],
  }
  while true {
    while !token_is_inline_end(ctx.peek(), policy) {
      match ctx.peek() {
        Backtick => parse_indexed_inline_code(ctx, delimiters, continue_line)
        _ =>
          parse_inline(
            ctx, policy, delimiters, links, delimiter_cursor, continue_line,
          )
      }
    }
    guard ctx.peek() is Newline && continue_line() else { break }
  }
  validate_delimiter_cursor_completion(
    event_index=delimiter_cursor.event_index,
    event_count=delimiter_cursor.events.length(),
    emphasis_depth=delimiter_cursor.emphasis_stack.length(),
  )
}

///|
fn[T] parse_indexed_inline_container(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  handler : ContinuationHandler[T],
) -> Unit {
  let continue_line = continuation_step(handler)
  parse_indexed_inline_container_with_continue_line(ctx, policy, continue_line)
}

///|
fn parse_indexed_inline_container_without_continuation(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
) -> Unit {
  parse_indexed_inline_container_with_continue_line(ctx, policy, () => false)
}

///|
fn parse_indexed_inline_code(
  ctx : @core.ParserContext[Token, SyntaxKind],
  delimiters : CodeSpanDelimiterIndex,
  continue_line : () -> Bool,
) -> Unit {
  let opener_start = ctx.current_token_range().start
  guard delimiters.eligible_openers.get(opener_start).unwrap_or(false) else {
    ctx.emit_token(BacktickToken)
    return
  }
  guard delimiters.successors.get(opener_start) is Some(closer_start) else {
    ctx.emit_token(BacktickToken)
    return
  }
  ctx.start_node(InlineCodeNode)
  ctx.emit_token(BacktickToken)
  while ctx.current_token_range().start != closer_start {
    if ctx.peek() is Newline {
      guard continue_line() else {
        abort("indexed code span crossed its container boundary")
      }
      continue
    }
    match ctx.peek() {
      Text(_) => ctx.emit_token(TextToken)
      Indentation(_) => ctx.emit_token(TextToken)
      Star => ctx.emit_token(StarToken)
      StarStar => ctx.emit_token(StarStarToken)
      Underscore => ctx.emit_token(TextToken)
      Backtick => ctx.emit_token(BacktickToken)
      LeftBracket => ctx.emit_token(LeftBracketToken)
      RightBracket => ctx.emit_token(RightBracketToken)
      LeftParen => ctx.emit_token(LeftParenToken)
      RightParen => ctx.emit_token(RightParenToken)
      _ => ctx.bump_error()
    }
  }
  ctx.emit_token(BacktickToken)
  ctx.finish_node()
}

///|
/// Parse a single inline element.
fn parse_inline(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  delimiters : CodeSpanDelimiterIndex,
  links : InlineLinkDelimiterIndex,
  delimiter_cursor : InlineDelimiterPlanCursor,
  continue_line : () -> Bool,
) -> Unit {
  if try_emit_planned_delimiter(ctx, delimiter_cursor) {
    return
  }
  match ctx.peek() {
    Star | StarStar | Underscore => ctx.emit_token(TextToken)
    Backtick => parse_indexed_inline_code(ctx, delimiters, continue_line)
    LeftBracket => {
      let opener_start = ctx.current_token_range().start
      if links.label_closers_by_open.get(opener_start) is Some(_) {
        parse_link(
          ctx, policy, delimiters, links, delimiter_cursor, continue_line,
        )
      } else {
        ctx.start_node(ErrorNode)
        ctx.emit_token(LeftBracketToken)
        ctx.finish_node()
      }
    }
    Text(_) => ctx.emit_token(TextToken)
    Indentation(_) => ctx.emit_token(TextToken)
    OrderedListMarker(_) if policy.allows_ordered_marker() =>
      ctx.emit_token(TextToken)
    _ =>
      // Unexpected inline token — emit as error
      ctx.bump_error()
  }
}

///|
/// Parse link: [text](url)
fn parse_link(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  delimiters : CodeSpanDelimiterIndex,
  links : InlineLinkDelimiterIndex,
  delimiter_cursor : InlineDelimiterPlanCursor,
  continue_line : () -> Bool,
) -> Unit {
  guard links.label_closers_by_open.get(ctx.current_token_range().start)
    is Some(label_closer_start) else {
    abort("parse_link requires a pre-indexed confirmed link")
  }
  ctx.start_node(LinkNode)
  ctx.emit_token(LeftBracketToken) // [
  // The link index owns bracket matching. Earlier unmatched brackets are
  // literal label text and must not terminate a confirmed outer label.
  while !token_is_inline_block_boundary(ctx.peek(), policy) &&
        ctx.current_token_range().start != label_closer_start {
    if ctx.peek() is Newline {
      guard continue_line() else {
        abort("indexed link label crossed its container boundary")
      }
      continue
    }
    match ctx.peek() {
      LeftBracket =>
        match links.label_closers_by_open.get(ctx.current_token_range().start) {
          None => ctx.emit_token(TextToken)
          Some(_) =>
            parse_inline(
              ctx, policy, delimiters, links, delimiter_cursor, continue_line,
            )
        }
      RightBracket => ctx.emit_token(TextToken)
      _ =>
        parse_inline(
          ctx, policy, delimiters, links, delimiter_cursor, continue_line,
        )
    }
  }
  if token_is_inline_block_boundary(ctx.peek(), policy) ||
    ctx.current_token_range().start != label_closer_start ||
    !(ctx.peek() is RightBracket) {
    abort("pre-indexed link label did not reach its closing bracket")
  }
  ctx.emit_token(RightBracketToken) // ]
  // Expect (url)
  if !(ctx.peek() is LeftParen) {
    abort("pre-indexed link label did not reach its destination")
  }
  guard links.destination_ends.get(ctx.current_token_range().start)
    is Some(destination_end) else {
    abort("parse_link requires a pre-indexed destination end")
  }
  ctx.emit_token(LeftParenToken) // (
  // The analysis pass is the single owner of destination balancing. Consume
  // raw destination tokens up to its exact outer closer rather than resolving
  // parentheses a second time in the imperative emission pass.
  while !is_inline_end(ctx.peek()) &&
        ctx.current_token_range().end < destination_end {
    match ctx.peek() {
      LeftParen => ctx.emit_token(LeftParenToken)
      RightParen => ctx.emit_token(RightParenToken)
      Text(_) => ctx.emit_token(TextToken)
      Star | StarStar | Underscore => ctx.emit_token(TextToken)
      Backtick => ctx.emit_token(BacktickToken)
      LeftBracket => ctx.emit_token(LeftBracketToken)
      RightBracket => ctx.emit_token(RightBracketToken)
      _ => ctx.bump_error()
    }
  }
  guard !is_inline_end(ctx.peek()) &&
    ctx.current_token_range().end == destination_end &&
    ctx.peek() is RightParen else {
    abort("pre-indexed link destination did not reach its closing parenthesis")
  }
  ctx.emit_token(RightParenToken)
  ctx.finish_node()
}
