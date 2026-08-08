// PROTOTYPE — guarded source-range inline analysis for the real Markdown shell.
//
// This path falls back for link forms that are not yet source-range safe.
// The existing full-token parser remains the correctness oracle.

///|
priv struct MarkdownSparseInlineEvent {
  kind : InlineAnalysisTokenKind
  start : Int
  end : Int
}

///|
priv struct MarkdownSparseInlineAnalysis {
  start : Int
  end : Int
  events : Array[MarkdownSparseInlineEvent]
}

///|
priv enum MarkdownSparseCodeCloser {
  NotCode
  Found(Int)
  Invalid
}

///|
fn markdown_sparse_is_event_kind(kind : InlineAnalysisTokenKind) -> Bool {
  match kind {
    AnalysisAsterisk
    | AnalysisUnderscore
    | AnalysisBacktick
    | AnalysisLeftBracket
    | AnalysisRightBracket
    | AnalysisLeftParen
    | AnalysisRightParen
    | AnalysisLineBoundary => true
    AnalysisOther => false
  }
}

///|
fn markdown_sparse_inline_analysis(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  continue_line : () -> Bool,
) -> MarkdownSparseInlineAnalysis? {
  let events : Array[MarkdownSparseInlineEvent] = []
  let mut start = -1
  let mut end = -1
  while true {
    while !token_is_inline_end(ctx.peek(), policy) {
      let range = ctx.current_token_range()
      if start < 0 {
        start = range.start
      }
      end = range.end
      let kind = inline_analysis_token_kind(ctx.peek())
      if markdown_sparse_is_event_kind(kind) {
        events.push({ kind, start: range.start, end: range.end })
      } else if ctx.peek() is Newline {
        return None
      }
      ctx.emit_current_token()
    }
    if ctx.peek() is Newline {
      let boundary_start = ctx.current_token_range().start
      if continue_line() {
        let next_start = ctx.current_token_range().start
        if start < 0 {
          start = boundary_start
        }
        end = next_start
        events.push({
          kind: AnalysisLineBoundary,
          start: boundary_start,
          end: next_start,
        })
      } else {
        break
      }
    } else {
      break
    }
  }
  if start < 0 {
    let range = ctx.current_token_range()
    start = range.start
    end = range.start
  }
  Some({ start, end, events })
}

///|
fn markdown_sparse_code_closer_index(
  events : Array[MarkdownSparseInlineEvent],
  index : Int,
  code_delimiters : CodeSpanDelimiterIndex,
) -> MarkdownSparseCodeCloser {
  let event = events[index]
  if event.kind != AnalysisBacktick {
    return NotCode
  }
  if !code_delimiters.eligible_openers.get(event.start).unwrap_or(false) {
    return NotCode
  }
  let closer_start = match code_delimiters.successors.get(event.start) {
    Some(closer_start) => closer_start
    None => return NotCode
  }
  for i = index + 1; i < events.length(); i = i + 1 {
    if events[i].start == closer_start {
      return Found(i)
    }
  }
  Invalid
}

///|
fn markdown_sparse_code_index(
  ctx : @core.ParserContext[Token, SyntaxKind],
  analysis : MarkdownSparseInlineAnalysis,
) -> CodeSpanDelimiterIndex {
  let index : CodeSpanDelimiterIndex = {
    eligible_openers: Map([]),
    successors: Map([]),
  }
  let previous_by_length : Map[Int, Int] = Map([])
  let mut source_cursor = analysis.start
  let mut previous_event_ends_escaped = false
  for event in analysis.events {
    let gap_ends_escaped = if event.start > source_cursor {
      text_ends_with_odd_backslashes(
        ctx.source_view(start=source_cursor, end=event.start),
      )
    } else {
      previous_event_ends_escaped
    }
    match event.kind {
      AnalysisBacktick => {
        index_code_span_delimiter_run(
          index,
          previous_by_length,
          event.start,
          event.end - event.start,
          !gap_ends_escaped,
        )
        previous_event_ends_escaped = false
      }
      AnalysisLineBoundary => previous_event_ends_escaped = false
      _ =>
        previous_event_ends_escaped = text_ends_with_odd_backslashes(
          ctx.source_view(start=event.start, end=event.end),
        )
    }
    source_cursor = event.end
  }
  index
}

///|
fn markdown_sparse_is_image(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opener_start : Int,
) -> Bool {
  guard opener_start > 0 else { return false }
  guard ctx.source_view(start=opener_start - 1, end=opener_start) == "!" else {
    return false
  }
  !text_ends_with_odd_backslashes(
    ctx.source_view(start=0, end=opener_start - 1),
  )
}

///|
fn markdown_sparse_destination_end(
  events : Array[MarkdownSparseInlineEvent],
  opener_index : Int,
) -> Int? {
  let mut depth = 0
  let mut index = opener_index
  while index < events.length() {
    match events[index].kind {
      AnalysisLineBoundary | AnalysisBacktick => return None
      AnalysisLeftParen => depth = depth + 1
      AnalysisRightParen => {
        depth = depth - 1
        if depth == 0 {
          return Some(index)
        }
      }
      _ => ()
    }
    index = index + 1
  }
  None
}

///|
fn markdown_sparse_destination_is_simple(
  ctx : @core.ParserContext[Token, SyntaxKind],
  events : Array[MarkdownSparseInlineEvent],
  opener_index : Int,
  destination_end : Int,
) -> Bool {
  ctx
  .source_view(
    start=events[opener_index].end,
    end=events[destination_end].start,
  )
  .all(fn(ch) {
    match ch {
      ' ' | '\t' | '\r' | '\n' | '<' | '>' | '\\' | '"' => false
      _ => true
    }
  })
}

///|
/// Guarded source-range link index. Reference links, separated destinations,
/// literal recovery, multiline destinations, and code/link conflicts fall back.
fn markdown_sparse_links(
  ctx : @core.ParserContext[Token, SyntaxKind],
  analysis : MarkdownSparseInlineAnalysis,
  code_delimiters : CodeSpanDelimiterIndex,
) -> InlineLinkDelimiterIndex? {
  let bracket_matches : Map[Int, InlineBracketMatch] = Map([])
  let bracket_stack : Array[InlineBracketFrame] = []
  let mut index = 0
  while index < analysis.events.length() {
    match
      markdown_sparse_code_closer_index(analysis.events, index, code_delimiters) {
      Found(closer) => {
        for code_index = index + 1
            code_index < closer
            code_index = code_index + 1 {
          if analysis.events[code_index].kind == AnalysisRightBracket &&
            bracket_stack.length() > 0 {
            return None
          }
        }
        index = closer + 1
      }
      Invalid => return None
      NotCode => {
        match analysis.events[index].kind {
          AnalysisLineBoundary => ()
          AnalysisLeftBracket =>
            bracket_stack.push({ index, code_conflict_generation: 0 })
          AnalysisRightBracket =>
            match bracket_stack.pop() {
              Some(opener) =>
                bracket_matches[opener.index] = {
                  closer_index: index,
                  code_conflict: false,
                }
              None => ()
            }
          _ => ()
        }
        index = index + 1
      }
    }
  }
  let links : InlineLinkDelimiterIndex = {
    candidates: [],
    bracket_matches,
    candidate_by_opener: Map([]),
    candidate_by_suffix: Map([]),
    candidate_by_label_closer: Map([]),
    code_conflict_openers: Map([]),
    code_conflict_closers: Map([]),
    code_conflict_parens: Map([]),
  }
  index = 0
  while index < analysis.events.length() {
    match
      markdown_sparse_code_closer_index(analysis.events, index, code_delimiters) {
      Found(closer) => index = closer + 1
      Invalid => return None
      NotCode => {
        if analysis.events[index].kind == AnalysisLeftBracket {
          match links.bracket_matches.get(index) {
            Some(label_match) => {
              let label_closer = label_match.closer_index
              let after_label = label_closer + 1
              if after_label < analysis.events.length() &&
                analysis.events[after_label].kind == AnalysisLeftParen {
                guard analysis.events[label_closer].end ==
                  analysis.events[after_label].start else {
                  return None
                }
                let destination_end = markdown_sparse_destination_end(
                  analysis.events,
                  after_label,
                )
                guard destination_end is Some(destination_end) else {
                  return None
                }
                guard markdown_sparse_destination_is_simple(
                  ctx,
                  analysis.events,
                  after_label,
                  destination_end,
                ) else {
                  return None
                }
                let candidate_index = links.candidates.length()
                links.candidates.push({
                  opener_start: analysis.events[index].start,
                  label_closer_start: analysis.events[label_closer].start,
                  suffix_start: analysis.events[after_label].start,
                  suffix_end: analysis.events[destination_end].end,
                  form: InlineTargetForm,
                  disposition: ValidLinkDisposition,
                  is_image: markdown_sparse_is_image(
                    ctx,
                    analysis.events[index].start,
                  ),
                  active: true,
                })
                links.candidate_by_opener[analysis.events[index].start] = candidate_index
                links.candidate_by_suffix[analysis.events[after_label].start] = candidate_index
                links.candidate_by_label_closer[analysis.events[label_closer].start] = candidate_index
              } else if after_label < analysis.events.length() &&
                analysis.events[after_label].kind == AnalysisLeftBracket &&
                links.bracket_matches.get(after_label) is Some(_) {
                return None
              }
            }
            None => ()
          }
        }
        index = index + 1
      }
    }
  }
  // Candidates are collected in source order. A single frontier proves that
  // supported candidates are disjoint without making the guard quadratic.
  let mut previous_suffix_end = -1
  for candidate in links.candidates {
    if candidate.opener_start < previous_suffix_end {
      return None
    }
    previous_suffix_end = candidate.suffix_end
  }
  index = 0
  while index < analysis.events.length() {
    match
      markdown_sparse_code_closer_index(analysis.events, index, code_delimiters) {
      Found(closer) => index = closer + 1
      Invalid => return None
      NotCode => {
        let event = analysis.events[index]
        match event.kind {
          AnalysisLeftBracket =>
            if links.candidate_by_opener.get(event.start) is None {
              return None
            }
          AnalysisRightBracket =>
            if links.candidate_by_label_closer.get(event.start) is None {
              return None
            }
          AnalysisLeftParen | AnalysisRightParen => {
            let mut owned = false
            for candidate in links.candidates {
              if event.start >= candidate.suffix_start &&
                event.end <= candidate.suffix_end {
                owned = true
                break
              }
            }
            if !owned {
              return None
            }
          }
          _ => ()
        }
        index = index + 1
      }
    }
  }
  Some(links)
}

///|
fn markdown_sparse_first_char_after(
  ctx : @core.ParserContext[Token, SyntaxKind],
  analysis : MarkdownSparseInlineAnalysis,
  offset : Int,
  next_index : Int,
) -> Char? {
  let next_start = if next_index < analysis.events.length() {
    analysis.events[next_index].start
  } else {
    analysis.end
  }
  if next_start > offset {
    first_char_in_inline_text(ctx.source_view(start=offset, end=next_start))
  } else if next_index < analysis.events.length() {
    match analysis.events[next_index].kind {
      AnalysisLineBoundary => Some('\n')
      _ =>
        first_char_in_inline_text(
          ctx.source_view(
            start=analysis.events[next_index].start,
            end=analysis.events[next_index].end,
          ),
        )
    }
  } else {
    None
  }
}

///|
fn markdown_sparse_event_last_char(
  ctx : @core.ParserContext[Token, SyntaxKind],
  event : MarkdownSparseInlineEvent,
) -> Char? {
  match event.kind {
    AnalysisLineBoundary => Some('\n')
    _ =>
      last_char_in_inline_text(
        ctx.source_view(start=event.start, end=event.end),
      )
  }
}

///|
fn markdown_sparse_delimiter_plan(
  ctx : @core.ParserContext[Token, SyntaxKind],
  analysis : MarkdownSparseInlineAnalysis,
  code_delimiters : CodeSpanDelimiterIndex,
  links : InlineLinkDelimiterIndex,
) -> DelimiterResolutionPlan? {
  let resolver_events : Array[DelimiterResolverEvent] = []
  let mut previous_char : Char? = None
  let mut source_cursor = analysis.start
  let mut index = 0
  while index < analysis.events.length() {
    let event = analysis.events[index]
    if source_cursor < event.start {
      previous_char = last_char_in_inline_text(
        ctx.source_view(start=source_cursor, end=event.start),
      )
    }
    match
      markdown_sparse_code_closer_index(analysis.events, index, code_delimiters) {
      Found(closer) => {
        resolver_events.push(
          OpaqueInlineEvent(
            DelimiterSourceRange(event.start, analysis.events[closer].end),
          ),
        )
        previous_char = Some('`')
        source_cursor = analysis.events[closer].end
        index = closer + 1
      }
      Invalid => return None
      NotCode =>
        match inline_link_candidate_for_suffix(links, event.start) {
          Some(candidate) => {
            let suffix_end = candidate.suffix_end
            let start = event.start
            while index < analysis.events.length() &&
                  analysis.events[index].end < suffix_end {
              index = index + 1
            }
            guard index < analysis.events.length() &&
              analysis.events[index].end == suffix_end else {
              return None
            }
            resolver_events.push(
              OpaqueInlineEvent(DelimiterSourceRange(start, suffix_end)),
            )
            previous_char = match candidate.form {
              InlineTargetForm => Some(')')
              FullReferenceForm | CollapsedReferenceForm => Some(']')
            }
            source_cursor = suffix_end
            index = index + 1
          }
          None => {
            if inline_link_candidate_for_opener(links, event.start) is Some(_) {
              resolver_events.push(PushLinkLabelScope)
            }
            match analysis_delimiter_marker(event.kind) {
              Some(marker) => {
                let start = event.start
                let mut end = event.end
                let mut next = index + 1
                while next < analysis.events.length() &&
                      analysis_delimiter_marker(analysis.events[next].kind) ==
                      Some(marker) &&
                      analysis.events[next].start == end {
                  end = analysis.events[next].end
                  next = next + 1
                }
                let after = markdown_sparse_first_char_after(
                  ctx, analysis, end, next,
                )
                resolver_events.push(
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
                source_cursor = end
                index = next
              }
              None => {
                previous_char = markdown_sparse_event_last_char(ctx, event)
                if inline_link_candidate_for_label_closer(links, event.start)
                  is Some(_) {
                  resolver_events.push(ResolveLinkLabelScope)
                }
                source_cursor = event.end
                index = index + 1
              }
            }
          }
        }
    }
  }
  Some(resolve_delimiter_events(resolver_events))
}

///|
/// Try the guarded source-range path. Returning false leaves the parser
/// cursor untouched because analysis collection runs inside lookahead.
fn try_markdown_sparse_inline_container(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  continue_line : () -> Bool,
) -> Bool {
  let analysis = ctx.lookahead(() => {
    markdown_sparse_inline_analysis(ctx, policy, continue_line)
  })
  guard analysis is Some(analysis) else { return false }
  let code_delimiters = markdown_sparse_code_index(ctx, analysis)
  let links = markdown_sparse_links(ctx, analysis, code_delimiters)
  guard links is Some(links) else { return false }
  let delimiter_plan = markdown_sparse_delimiter_plan(
    ctx, analysis, code_delimiters, links,
  )
  guard delimiter_plan is Some(delimiter_plan) else { return false }
  let delimiter_cursor : InlineDelimiterPlanCursor = {
    events: delimiter_plan.events,
    event_index: 0,
    emphasis_stack: [],
  }
  while true {
    while !token_is_inline_end(ctx.peek(), policy) {
      match ctx.peek() {
        Backtick =>
          parse_indexed_inline_code(ctx, code_delimiters, continue_line)
        _ =>
          parse_inline(
            ctx, policy, code_delimiters, links, delimiter_cursor, continue_line,
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
  true
}
