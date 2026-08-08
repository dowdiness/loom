// PROTOTYPE — throwaway cmark-informed inline event-index experiment.
//
// Question: can the inline analysis bank omit ordinary text payloads while
// retaining the source ranges and delimiter events needed by Loom's current
// analysis stage?
//
// This intentionally does not change the parser. It compares a current-like
// owned bank with a sparse source-range bank over the same lexer output.
// Run only this prototype with:
//   moon bench --release --target native inline_event_index_prototype_wbtest.mbt

///|
priv struct PrototypeSparseEvent {
  kind : InlineAnalysisTokenKind
  start : Int
  end : Int
}

///|
fn prototype_analysis_kind(token : Token) -> InlineAnalysisTokenKind {
  match token {
    Newline => AnalysisLineBoundary
    _ => inline_analysis_token_kind(token)
  }
}

///|
fn prototype_is_sparse_kind(kind : InlineAnalysisTokenKind) -> Bool {
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
/// Approximation of the current analysis-bank construction. It intentionally
/// owns a String for every lexer token, like InlineAnalysisToken currently does.
fn prototype_current_bank(
  source : String,
  tokens : Array[@core.TokenInfo[Token]],
) -> Array[InlineAnalysisToken] {
  let bank : Array[InlineAnalysisToken] = []
  let mut offset = 0
  for info in tokens {
    let start = offset
    let end = start + info.len
    offset = end
    match info.token {
      EOF => ()
      Newline =>
        bank.push({
          kind: AnalysisLineBoundary,
          text: "\n",
          start,
          end,
          first: Some('\n'),
          last: Some('\n'),
          ends_with_odd_backslashes: false,
        })
      _ => {
        let text = source.view(start_offset=start, end_offset=end).to_owned()
        bank.push({
          kind: inline_analysis_token_kind(info.token),
          first: first_char_in_inline_text(text.view()),
          last: last_char_in_inline_text(text.view()),
          ends_with_odd_backslashes: text_ends_with_odd_backslashes(text.view()),
          text,
          start,
          end,
        })
      }
    }
  }
  bank
}

///|
/// Candidate representation: only syntax-bearing events retain a range. The
/// source remains authoritative; ordinary text is recovered from StringView
/// only when a downstream analysis needs neighboring characters.
fn prototype_sparse_bank(
  tokens : Array[@core.TokenInfo[Token]],
) -> Array[PrototypeSparseEvent] {
  let events : Array[PrototypeSparseEvent] = []
  let mut offset = 0
  for info in tokens {
    let start = offset
    let end = start + info.len
    offset = end
    guard info.token != EOF else { continue }
    let kind = prototype_analysis_kind(info.token)
    if prototype_is_sparse_kind(kind) {
      events.push({ kind, start, end })
    }
  }
  events
}

///|
fn prototype_char_code(ch : Char?) -> Int {
  match ch {
    Some(ch) => ch.to_int()
    None => -1
  }
}

///|
/// Sparse equivalent of build_code_span_delimiter_index. Omitted text is
/// inspected as a source gap only when it can affect the next backtick's
/// escaped-opener decision.
fn prototype_sparse_code_span_delimiter_index(
  source : String,
  events : Array[PrototypeSparseEvent],
) -> CodeSpanDelimiterIndex {
  let index : CodeSpanDelimiterIndex = {
    eligible_openers: Map([]),
    successors: Map([]),
  }
  let previous_by_length : Map[Int, Int] = Map([])
  let mut source_cursor = 0
  let mut previous_event_ends_escaped = false
  for event in events {
    let gap_ends_escaped = if event.start > source_cursor {
      text_ends_with_odd_backslashes(
        source.view(start_offset=source_cursor, end_offset=event.start),
      )
    } else {
      false
    }
    match event.kind {
      AnalysisBacktick => {
        let preceding_text_ends_escaped = if event.start > source_cursor {
          gap_ends_escaped
        } else {
          previous_event_ends_escaped
        }
        index_code_span_delimiter_run(
          index,
          previous_by_length,
          event.start,
          event.end - event.start,
          !preceding_text_ends_escaped,
        )
        previous_event_ends_escaped = false
      }
      _ => {
        let event_text = source.view(
          start_offset=event.start,
          end_offset=event.end,
        )
        previous_event_ends_escaped = text_ends_with_odd_backslashes(event_text)
      }
    }
    source_cursor = event.end
  }
  index
}

///|
fn prototype_assert_bool_map_equal(
  expected : Map[Int, Bool],
  actual : Map[Int, Bool],
) -> Unit raise {
  let mut expected_count = 0
  for key, value in expected {
    expected_count = expected_count + 1
    assert_eq(actual.get(key), Some(value))
  }
  let mut actual_count = 0
  for key, value in actual {
    actual_count = actual_count + 1
    assert_eq(expected.get(key), Some(value))
  }
  assert_eq(expected_count, actual_count)
}

///|
fn prototype_assert_int_map_equal(
  expected : Map[Int, Int],
  actual : Map[Int, Int],
) -> Unit raise {
  let mut expected_count = 0
  for key, value in expected {
    expected_count = expected_count + 1
    assert_eq(actual.get(key), Some(value))
  }
  let mut actual_count = 0
  for key, value in actual {
    actual_count = actual_count + 1
    assert_eq(expected.get(key), Some(value))
  }
  assert_eq(expected_count, actual_count)
}

///|
fn prototype_assert_code_span_indexes_equal(
  expected : CodeSpanDelimiterIndex,
  actual : CodeSpanDelimiterIndex,
) -> Unit raise {
  prototype_assert_bool_map_equal(
    expected.eligible_openers,
    actual.eligible_openers,
  )
  prototype_assert_int_map_equal(expected.successors, actual.successors)
}

///|
fn prototype_sparse_code_closer_index(
  events : Array[PrototypeSparseEvent],
  index : Int,
  code_delimiters : CodeSpanDelimiterIndex,
) -> Int? {
  let event = events[index]
  guard event.kind == AnalysisBacktick else { return None }
  guard code_delimiters.eligible_openers.get(event.start).unwrap_or(false) else {
    return None
  }
  guard code_delimiters.successors.get(event.start) is Some(closer_start) else {
    return None
  }
  for i = index + 1; i < events.length(); i = i + 1 {
    if events[i].start == closer_start {
      return Some(i)
    }
  }
  abort("PROTOTYPE sparse code delimiter points outside its event stream")
}

///|
fn prototype_sparse_is_image(source : String, opener_start : Int) -> Bool {
  guard opener_start > 0 else { return false }
  guard source.get_char(opener_start - 1) == Some('!') else { return false }
  !text_ends_with_odd_backslashes(
    source.view(start_offset=0, end_offset=opener_start - 1),
  )
}

///|
/// Find a balanced, single-line inline destination. More complicated
/// destination forms deliberately return None so the production implementation
/// can fall back to the existing full-token index.
fn prototype_sparse_destination_end(
  events : Array[PrototypeSparseEvent],
  opener_index : Int,
) -> Int? {
  let mut depth = 0
  let mut index = opener_index
  while index < events.length() {
    let event = events[index]
    match event.kind {
      AnalysisLineBoundary => return None
      AnalysisBacktick => return None
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
/// Guarded link-index prototype. It supports complete inline-target links with
/// balanced, single-line destinations. References, separated destinations,
/// literal recovery, and code/link conflicts intentionally fall back to None.
fn prototype_sparse_inline_links(
  source : String,
  events : Array[PrototypeSparseEvent],
  code_delimiters : CodeSpanDelimiterIndex,
) -> InlineLinkDelimiterIndex? {
  let bracket_matches : Map[Int, InlineBracketMatch] = Map([])
  let bracket_stack : Array[InlineBracketFrame] = []
  let mut index = 0
  while index < events.length() {
    match prototype_sparse_code_closer_index(events, index, code_delimiters) {
      Some(closer) => {
        for code_index = index + 1
            code_index < closer
            code_index = code_index + 1 {
          if events[code_index].kind == AnalysisRightBracket &&
            bracket_stack.length() > 0 {
            return None
          }
        }
        index = closer + 1
      }
      None => {
        match events[index].kind {
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
  while index < events.length() {
    match prototype_sparse_code_closer_index(events, index, code_delimiters) {
      Some(closer) => index = closer + 1
      None => {
        if events[index].kind == AnalysisLeftBracket {
          match links.bracket_matches.get(index) {
            Some(label_match) => {
              let label_closer = label_match.closer_index
              let after_label = label_closer + 1
              if after_label < events.length() &&
                events[after_label].kind == AnalysisLeftParen {
                guard events[label_closer].end == events[after_label].start else {
                  return None
                }
                let destination_end = prototype_sparse_destination_end(
                  events, after_label,
                )
                guard destination_end is Some(destination_end) else {
                  return None
                }
                let candidate_index = links.candidates.length()
                links.candidates.push({
                  opener_start: events[index].start,
                  label_closer_start: events[label_closer].start,
                  suffix_start: events[after_label].start,
                  suffix_end: events[destination_end].end,
                  form: InlineTargetForm,
                  disposition: ValidLinkDisposition,
                  is_image: prototype_sparse_is_image(
                    source,
                    events[index].start,
                  ),
                  active: true,
                })
                links.candidate_by_opener[events[index].start] = candidate_index
                links.candidate_by_suffix[events[after_label].start] = candidate_index
                links.candidate_by_label_closer[events[label_closer].start] = candidate_index
              } else if after_label < events.length() &&
                events[after_label].kind == AnalysisLeftBracket &&
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
  Some(links)
}

///|
fn prototype_same_link_form(
  left : InlineLinkSyntacticForm,
  right : InlineLinkSyntacticForm,
) -> Bool {
  match (left, right) {
    (InlineTargetForm, InlineTargetForm)
    | (FullReferenceForm, FullReferenceForm)
    | (CollapsedReferenceForm, CollapsedReferenceForm) => true
    _ => false
  }
}

///|
fn prototype_same_link_disposition(
  left : InlineLinkCandidateDisposition,
  right : InlineLinkCandidateDisposition,
) -> Bool {
  match (left, right) {
    (ValidLinkDisposition, ValidLinkDisposition)
    | (LiteralLinkDisposition, LiteralLinkDisposition) => true
    _ => false
  }
}

///|
fn prototype_assert_link_candidates_equal(
  expected : InlineLinkDelimiterIndex,
  actual : InlineLinkDelimiterIndex,
) -> Unit raise {
  assert_eq(expected.candidates.length(), actual.candidates.length())
  for index = 0; index < expected.candidates.length(); index = index + 1 {
    let left = expected.candidates[index]
    let right = actual.candidates[index]
    assert_eq(left.opener_start, right.opener_start)
    assert_eq(left.label_closer_start, right.label_closer_start)
    assert_eq(left.suffix_start, right.suffix_start)
    assert_eq(left.suffix_end, right.suffix_end)
    assert_true(prototype_same_link_form(left.form, right.form))
    assert_true(
      prototype_same_link_disposition(left.disposition, right.disposition),
    )
    assert_eq(left.is_image, right.is_image)
    assert_eq(left.active, right.active)
  }
}

///|
fn prototype_sparse_first_char_after(
  source : String,
  events : Array[PrototypeSparseEvent],
  offset : Int,
  next_index : Int,
) -> Char? {
  let next_start = if next_index < events.length() {
    events[next_index].start
  } else {
    source.length()
  }
  if next_start > offset {
    first_char_in_inline_text(
      source.view(start_offset=offset, end_offset=next_start),
    )
  } else if next_index < events.length() {
    match events[next_index].kind {
      AnalysisLineBoundary => Some('\n')
      _ =>
        first_char_in_inline_text(
          source.view(
            start_offset=events[next_index].start,
            end_offset=events[next_index].end,
          ),
        )
    }
  } else {
    None
  }
}

///|
fn prototype_sparse_event_last_char(
  source : String,
  event : PrototypeSparseEvent,
) -> Char? {
  match event.kind {
    AnalysisLineBoundary => Some('\n')
    _ =>
      last_char_in_inline_text(
        source.view(start_offset=event.start, end_offset=event.end),
      )
  }
}

///|
/// Sparse equivalent of build_inline_delimiter_plan. The resolver itself is
/// reused unchanged; only the source-order event collection is specialized.
fn prototype_sparse_inline_delimiter_plan(
  source : String,
  events : Array[PrototypeSparseEvent],
  code_delimiters : CodeSpanDelimiterIndex,
  links : InlineLinkDelimiterIndex,
) -> DelimiterResolutionPlan {
  let resolver_events : Array[DelimiterResolverEvent] = []
  let mut previous_char : Char? = None
  let mut source_cursor = 0
  let mut index = 0
  while index < events.length() {
    let event = events[index]
    if source_cursor < event.start {
      previous_char = last_char_in_inline_text(
        source.view(start_offset=source_cursor, end_offset=event.start),
      )
    }
    match prototype_sparse_code_closer_index(events, index, code_delimiters) {
      Some(closer) => {
        resolver_events.push(
          OpaqueInlineEvent(
            DelimiterSourceRange(event.start, events[closer].end),
          ),
        )
        previous_char = Some('`')
        source_cursor = events[closer].end
        index = closer + 1
      }
      None =>
        match inline_link_candidate_for_suffix(links, event.start) {
          Some(candidate) => {
            let suffix_end = candidate.suffix_end
            let start = event.start
            while index < events.length() && events[index].end < suffix_end {
              index = index + 1
            }
            guard index < events.length() && events[index].end == suffix_end else {
              abort(
                "PROTOTYPE sparse link range points outside its event stream",
              )
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
                while next < events.length() &&
                      analysis_delimiter_marker(events[next].kind) ==
                      Some(marker) &&
                      events[next].start == end {
                  end = events[next].end
                  next = next + 1
                }
                let after = prototype_sparse_first_char_after(
                  source, events, end, next,
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
                previous_char = prototype_sparse_event_last_char(source, event)
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
  resolve_delimiter_events(resolver_events)
}

///|
fn prototype_collect_sparse_inline_events(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  continue_line : () -> Bool,
) -> Array[PrototypeSparseEvent] {
  let events : Array[PrototypeSparseEvent] = []
  while true {
    while !token_is_inline_end(ctx.peek(), policy) {
      let range = ctx.current_token_range()
      let kind = inline_analysis_token_kind(ctx.peek())
      if prototype_is_sparse_kind(kind) {
        events.push({ kind, start: range.start, end: range.end })
      }
      ctx.emit_current_token()
    }
    if ctx.peek() is Newline {
      let boundary_start = ctx.current_token_range().start
      if continue_line() {
        let next_start = ctx.current_token_range().start
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
  events
}

///|
/// Test-only parser shell. The lookahead collector preserves the existing
/// parser cursor, so returning false is a safe full-token fallback.
fn prototype_parse_sparse_inline_container_with_continue_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
  source : String,
  policy : InlineParsePolicy,
  continue_line : () -> Bool,
) -> Bool {
  let events = ctx.lookahead(() => {
    prototype_collect_sparse_inline_events(ctx, policy, continue_line)
  })
  let code_delimiters = prototype_sparse_code_span_delimiter_index(
    source, events,
  )
  let links = prototype_sparse_inline_links(source, events, code_delimiters)
  guard links is Some(links) else { return false }
  let delimiter_plan = prototype_sparse_inline_delimiter_plan(
    source, events, code_delimiters, links,
  )
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

///|
fn prototype_parse_sparse_single_paragraph(
  ctx : @core.ParserContext[Token, SyntaxKind],
  source : String,
) -> Unit {
  ctx.node(ParagraphNode, fn() {
    let continue_line = () => {
      if ctx.peek() is Newline && ctx.peek_nth(1) != EOF {
        ctx.emit_token(NewlineToken)
        true
      } else {
        false
      }
    }
    let used_sparse = prototype_parse_sparse_inline_container_with_continue_line(
      ctx,
      source,
      InlineParsePolicy::paragraph(),
      continue_line,
    )
    if !used_sparse {
      parse_indexed_inline_container_with_continue_line(
        ctx,
        InlineParsePolicy::paragraph(),
        continue_line,
      )
    }
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
  })
}

///|
fn prototype_parse_full_single_paragraph(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  ctx.node(ParagraphNode, fn() {
    let continue_line = () => {
      if ctx.peek() is Newline && ctx.peek_nth(1) != EOF {
        ctx.emit_token(NewlineToken)
        true
      } else {
        false
      }
    }
    parse_indexed_inline_container_full_token_with_continue_line(
      ctx,
      InlineParsePolicy::paragraph(),
      continue_line,
    )
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
  })
}

///|
fn prototype_single_paragraph_parse(
  source_id : @core.SourceId,
  source : String,
  sparse : Bool,
) -> (@seam.CstNode, @core.DiagnosticSet) raise Failure {
  let tokens = tokenize(source) catch {
    _ => abort("PROTOTYPE parser shell lexer failure")
  }
  @core.parse_with(source_id, source, markdown_spec, _source => tokens, ctx => {
    if sparse {
      prototype_parse_sparse_single_paragraph(ctx, source)
    } else {
      prototype_parse_full_single_paragraph(ctx)
    }
  })
}

///|
fn prototype_assert_delimiter_plans_equal(
  expected : DelimiterResolutionPlan,
  actual : DelimiterResolutionPlan,
) -> Unit raise {
  assert_eq(expected.events.iter().to_array(), actual.events.iter().to_array())
  assert_eq(expected.stats.run_count, actual.stats.run_count)
  assert_eq(expected.stats.opener_checks, actual.stats.opener_checks)
}

///|
fn prototype_current_event_checksum(bank : Array[InlineAnalysisToken]) -> Int {
  let mut checksum = 0
  for event in bank {
    if prototype_is_sparse_kind(event.kind) {
      checksum = checksum +
        event.start +
        event.end +
        prototype_char_code(event.first) * 3 +
        prototype_char_code(event.last) * 5 +
        (if event.ends_with_odd_backslashes { 7 } else { 0 })
    }
  }
  checksum
}

///|
fn prototype_sparse_event_checksum(
  source : String,
  events : Array[PrototypeSparseEvent],
) -> Int {
  let mut checksum = 0
  for event in events {
    let view = source.view(start_offset=event.start, end_offset=event.end)
    let (first, last, odd_backslashes) = match event.kind {
      AnalysisLineBoundary => (Some('\n'), Some('\n'), false)
      _ =>
        (
          first_char_in_inline_text(view),
          last_char_in_inline_text(view),
          text_ends_with_odd_backslashes(view),
        )
    }
    checksum = checksum +
      event.start +
      event.end +
      prototype_char_code(first) * 3 +
      prototype_char_code(last) * 5 +
      (if odd_backslashes { 7 } else { 0 })
  }
  checksum
}

///|
fn prototype_tokens(source : String) -> Array[@core.TokenInfo[Token]] {
  tokenize(source) catch {
    _ => abort("PROTOTYPE lexer failure")
  }
}

///|
fn prototype_inline_source(
  repeats : Int,
  heavy : Bool,
  newline : String,
) -> String {
  let buffer = StringBuilder::new()
  for i = 0; i < repeats; i = i + 1 {
    let n = i.to_string()
    if heavy {
      buffer.write_string(
        "outer **bold " +
        n +
        "** and *italic* with `code` and [link](url) _word_" +
        newline,
      )
    } else {
      buffer.write_string(
        "ordinary paragraph text " +
        n +
        " with a few words and no delimiters" +
        newline,
      )
    }
  }
  buffer.to_string()
}

///|
fn prototype_inline_link_source(repeats : Int) -> String {
  let buffer = StringBuilder::new()
  for i = 0; i < repeats; i = i + 1 {
    buffer.write_string("[link-" + i.to_string() + "](url) ")
  }
  buffer.write_string("\n")
  buffer.to_string()
}

///|
fn prototype_bench_current_bank(b : @bench.T, source : String) -> Unit {
  let tokens = prototype_tokens(source)
  b.bench(fn() { b.keep(prototype_current_bank(source, tokens)) })
}

///|
fn prototype_bench_sparse_bank(b : @bench.T, source : String) -> Unit {
  let tokens = prototype_tokens(source)
  b.bench(fn() { b.keep(prototype_sparse_bank(tokens)) })
}

///|
fn prototype_bench_current_analysis(b : @bench.T, source : String) -> Unit {
  let tokens = prototype_tokens(source)
  b.bench(fn() {
    let bank = prototype_current_bank(source, tokens)
    b.keep(prototype_current_event_checksum(bank))
  })
}

///|
fn prototype_bench_sparse_analysis(b : @bench.T, source : String) -> Unit {
  let tokens = prototype_tokens(source)
  b.bench(fn() {
    let events = prototype_sparse_bank(tokens)
    b.keep(prototype_sparse_event_checksum(source, events))
  })
}

///|
fn prototype_bench_current_code_index(b : @bench.T, source : String) -> Unit {
  let tokens = prototype_tokens(source)
  let bank = prototype_current_bank(source, tokens)
  b.bench(fn() { b.keep(build_code_span_delimiter_index(bank)) })
}

///|
fn prototype_bench_sparse_code_index(b : @bench.T, source : String) -> Unit {
  let tokens = prototype_tokens(source)
  let events = prototype_sparse_bank(tokens)
  b.bench(fn() {
    b.keep(prototype_sparse_code_span_delimiter_index(source, events))
  })
}

///|
fn prototype_bench_current_code_pipeline(b : @bench.T, source : String) -> Unit {
  let tokens = prototype_tokens(source)
  b.bench(fn() {
    let bank = prototype_current_bank(source, tokens)
    b.keep(build_code_span_delimiter_index(bank))
  })
}

///|
fn prototype_bench_sparse_code_pipeline(b : @bench.T, source : String) -> Unit {
  let tokens = prototype_tokens(source)
  b.bench(fn() {
    let events = prototype_sparse_bank(tokens)
    b.keep(prototype_sparse_code_span_delimiter_index(source, events))
  })
}

///|
fn prototype_bench_current_links(b : @bench.T, source : String) -> Unit {
  let tokens = prototype_tokens(source)
  let bank = prototype_current_bank(source, tokens)
  let code_delimiters = build_code_span_delimiter_index(bank)
  b.bench(fn() { b.keep(index_inline_links(bank, code_delimiters)) })
}

///|
fn prototype_bench_sparse_links(b : @bench.T, source : String) -> Unit {
  let tokens = prototype_tokens(source)
  let events = prototype_sparse_bank(tokens)
  let code_delimiters = prototype_sparse_code_span_delimiter_index(
    source, events,
  )
  guard prototype_sparse_inline_links(source, events, code_delimiters)
    is Some(_) else {
    abort("PROTOTYPE link fixture is outside the sparse guard")
  }
  b.bench(fn() {
    b.keep(prototype_sparse_inline_links(source, events, code_delimiters))
  })
}

///|
fn prototype_bench_current_link_pipeline(b : @bench.T, source : String) -> Unit {
  let tokens = prototype_tokens(source)
  b.bench(fn() {
    let bank = prototype_current_bank(source, tokens)
    let code_delimiters = build_code_span_delimiter_index(bank)
    b.keep(index_inline_links(bank, code_delimiters))
  })
}

///|
fn prototype_bench_sparse_link_pipeline(b : @bench.T, source : String) -> Unit {
  let tokens = prototype_tokens(source)
  b.bench(fn() {
    let events = prototype_sparse_bank(tokens)
    let code_delimiters = prototype_sparse_code_span_delimiter_index(
      source, events,
    )
    b.keep(prototype_sparse_inline_links(source, events, code_delimiters))
  })
}

///|
fn prototype_bench_current_delimiter_plan(
  b : @bench.T,
  source : String,
) -> Unit {
  let tokens = prototype_tokens(source)
  let bank = prototype_current_bank(source, tokens)
  let code_delimiters = build_code_span_delimiter_index(bank)
  let links = index_inline_links(bank, code_delimiters)
  b.bench(fn() {
    b.keep(build_inline_delimiter_plan(bank, code_delimiters, links))
  })
}

///|
fn prototype_bench_sparse_delimiter_plan(b : @bench.T, source : String) -> Unit {
  let tokens = prototype_tokens(source)
  let events = prototype_sparse_bank(tokens)
  let code_delimiters = prototype_sparse_code_span_delimiter_index(
    source, events,
  )
  let links = prototype_sparse_inline_links(source, events, code_delimiters)
  guard links is Some(links) else {
    abort("PROTOTYPE delimiter fixture is outside the sparse guard")
  }
  b.bench(fn() {
    b.keep(
      prototype_sparse_inline_delimiter_plan(
        source, events, code_delimiters, links,
      ),
    )
  })
}

///|
fn prototype_bench_current_delimiter_pipeline(
  b : @bench.T,
  source : String,
) -> Unit {
  let tokens = prototype_tokens(source)
  b.bench(fn() {
    let bank = prototype_current_bank(source, tokens)
    let code_delimiters = build_code_span_delimiter_index(bank)
    let links = index_inline_links(bank, code_delimiters)
    b.keep(build_inline_delimiter_plan(bank, code_delimiters, links))
  })
}

///|
fn prototype_bench_sparse_delimiter_pipeline(
  b : @bench.T,
  source : String,
) -> Unit {
  let tokens = prototype_tokens(source)
  b.bench(fn() {
    let events = prototype_sparse_bank(tokens)
    let code_delimiters = prototype_sparse_code_span_delimiter_index(
      source, events,
    )
    let links = prototype_sparse_inline_links(source, events, code_delimiters)
    b.keep(
      match links {
        Some(links) =>
          prototype_sparse_inline_delimiter_plan(
            source, events, code_delimiters, links,
          )
        None => abort("PROTOTYPE delimiter fixture is outside the sparse guard")
      },
    )
  })
}

///|
fn prototype_bench_current_parser_shell(b : @bench.T, source : String) -> Unit {
  let source_id = @core.SourceId("prototype-parser-shell")
  b.bench(fn() {
    let (tree, diagnostics) = try! prototype_single_paragraph_parse(
      source_id, source, false,
    )
    b.keep(tree)
    b.keep(diagnostics)
  })
}

///|
fn prototype_bench_sparse_parser_shell(b : @bench.T, source : String) -> Unit {
  let source_id = @core.SourceId("prototype-parser-shell")
  b.bench(fn() {
    let (tree, diagnostics) = try! prototype_single_paragraph_parse(
      source_id, source, true,
    )
    b.keep(tree)
    b.keep(diagnostics)
  })
}

///|
/// Differential smoke check. This is deliberately small: it checks that the
/// sparse event sequence and the source-derived delimiter facts match the
/// current-like bank for ASCII, Unicode, escaped markers, and line endings.
test "PROTOTYPE sparse events preserve current analysis facts" {
  let sources = [
    "plain 😈 text\n**bold** and [link](url)\n", "escaped \\*literal `code` _word_\r\nnext\rlast",
    "[日本語](url) **強調**\n",
  ]
  for source in sources {
    let tokens = prototype_tokens(source)
    let current = prototype_current_bank(source, tokens)
    let sparse = prototype_sparse_bank(tokens)
    let mut sparse_index = 0
    for event in current {
      if prototype_is_sparse_kind(event.kind) {
        let candidate = sparse[sparse_index]
        assert_true(candidate.kind == event.kind)
        assert_eq(candidate.start, event.start)
        assert_eq(candidate.end, event.end)
        sparse_index = sparse_index + 1
      }
    }
    assert_eq(sparse_index, sparse.length())
    assert_eq(
      prototype_current_event_checksum(current),
      prototype_sparse_event_checksum(source, sparse),
    )
  }
}

///|
test "PROTOTYPE invalid sparse code mapping is classified as fallback" {
  let events : Array[MarkdownSparseInlineEvent] = [
    { kind: AnalysisBacktick, start: 0, end: 1 },
  ]
  let code_delimiters : CodeSpanDelimiterIndex = {
    eligible_openers: Map([]),
    successors: Map([]),
  }
  code_delimiters.eligible_openers[0] = true
  code_delimiters.successors[0] = 2
  assert_true(
    match markdown_sparse_code_closer_index(events, 0, code_delimiters) {
      Invalid => true
      _ => false
    },
  )
}

///|
test "PROTOTYPE sparse code-span index matches current index" {
  let sources = [
    "before `code` after\n",
    "escaped \\`literal` and \\\\`code`\r\n",
    "日本語 `コード` and ``double``\rlast",
    prototype_inline_source(32, true, "\n"),
  ]
  for source in sources {
    let tokens = prototype_tokens(source)
    let current_bank = prototype_current_bank(source, tokens)
    let sparse_events = prototype_sparse_bank(tokens)
    let expected = build_code_span_delimiter_index(current_bank)
    let actual = prototype_sparse_code_span_delimiter_index(
      source, sparse_events,
    )
    prototype_assert_code_span_indexes_equal(expected, actual)
  }
}

///|
test "PROTOTYPE guarded sparse link index matches current index" {
  let sources = [
    "before [link](url) after\n",
    "[nested](https://example.test/a_(b)) and [second](url)\n",
    "![image](url) and [link](url)\n",
    prototype_inline_source(32, true, "\n"),
  ]
  for source in sources {
    let tokens = prototype_tokens(source)
    let current_bank = prototype_current_bank(source, tokens)
    let sparse_events = prototype_sparse_bank(tokens)
    let expected_code = build_code_span_delimiter_index(current_bank)
    let actual_code = prototype_sparse_code_span_delimiter_index(
      source, sparse_events,
    )
    prototype_assert_code_span_indexes_equal(expected_code, actual_code)
    let expected = index_inline_links(current_bank, expected_code)
    let actual = prototype_sparse_inline_links(
      source, sparse_events, actual_code,
    )
    guard actual is Some(actual) else {
      abort("PROTOTYPE guarded link fixture unexpectedly fell back")
    }
    prototype_assert_link_candidates_equal(expected, actual)
  }
}

///|
test "PROTOTYPE sparse link guard falls back on unsupported forms" {
  let sources = ["[label] (url)\n", "[label][reference]\n"]
  for source in sources {
    let tokens = prototype_tokens(source)
    let events = prototype_sparse_bank(tokens)
    let bank = prototype_current_bank(source, tokens)
    let code_delimiters = prototype_sparse_code_span_delimiter_index(
      source, events,
    )
    let current_code = build_code_span_delimiter_index(bank)
    prototype_assert_code_span_indexes_equal(current_code, code_delimiters)
    assert_true(
      prototype_sparse_inline_links(source, events, code_delimiters) is None,
    )
  }
}

///|
test "PROTOTYPE sparse delimiter plan matches current plan" {
  let sources = [
    "*italic* and **strong** with _under_\n",
    "outside *[inside](url) tail* and `*opaque*`\n",
    "日本語 *強調*、**強い**、[link](url)\n",
    prototype_inline_source(32, true, "\n"),
  ]
  for source in sources {
    let tokens = prototype_tokens(source)
    let current_bank = prototype_current_bank(source, tokens)
    let sparse_events = prototype_sparse_bank(tokens)
    let current_code = build_code_span_delimiter_index(current_bank)
    let sparse_code = prototype_sparse_code_span_delimiter_index(
      source, sparse_events,
    )
    prototype_assert_code_span_indexes_equal(current_code, sparse_code)
    let current_links = index_inline_links(current_bank, current_code)
    let sparse_links = prototype_sparse_inline_links(
      source, sparse_events, sparse_code,
    )
    guard sparse_links is Some(sparse_links) else {
      abort("PROTOTYPE delimiter fixture unexpectedly fell back")
    }
    prototype_assert_link_candidates_equal(current_links, sparse_links)
    prototype_assert_delimiter_plans_equal(
      build_inline_delimiter_plan(current_bank, current_code, current_links),
      prototype_sparse_inline_delimiter_plan(
        source, sparse_events, sparse_code, sparse_links,
      ),
    )
  }
}

///|
test "PROTOTYPE parser shell sparse path matches full-token path" {
  let sources = [
    "*italic* and **strong** with `code` and [link](url)\n",
    "outside *[inside](url) tail* and `*opaque*`\n",
    "日本語 *強調*、**強い**、[link](url)\n",
    "[label] (url) and [label][reference]\n",
    prototype_inline_source(32, true, "\n"),
    prototype_inline_link_source(256),
  ]
  for source in sources {
    let source_id = @core.SourceId("prototype-sparse-shell")
    let (full_tree, full_diagnostics) = try! prototype_single_paragraph_parse(
      source_id, source, false,
    )
    let (sparse_tree, sparse_diagnostics) = try! prototype_single_paragraph_parse(
      source_id, source, true,
    )
    assert_eq(sparse_tree, full_tree)
    assert_eq(sparse_diagnostics, full_diagnostics)
    let (production_tree, production_diagnostics) = try! parse_cst(
      source_id, source,
    )
    assert_eq(full_tree, production_tree)
    assert_eq(full_diagnostics, production_diagnostics)
  }
}

///|
test "PROTOTYPE current-owned bank, plain 250 lines" (b : @bench.T) {
  prototype_bench_current_bank(b, prototype_inline_source(250, false, "\n"))
}

///|
test "PROTOTYPE sparse bank, plain 250 lines" (b : @bench.T) {
  prototype_bench_sparse_bank(b, prototype_inline_source(250, false, "\n"))
}

///|
test "PROTOTYPE current-owned bank, delimiter-heavy 250 lines" (b : @bench.T) {
  prototype_bench_current_bank(b, prototype_inline_source(250, true, "\n"))
}

///|
test "PROTOTYPE sparse bank, delimiter-heavy 250 lines" (b : @bench.T) {
  prototype_bench_sparse_bank(b, prototype_inline_source(250, true, "\n"))
}

///|
test "PROTOTYPE current analysis, delimiter-heavy 250 lines" (b : @bench.T) {
  prototype_bench_current_analysis(b, prototype_inline_source(250, true, "\n"))
}

///|
test "PROTOTYPE sparse analysis, delimiter-heavy 250 lines" (b : @bench.T) {
  prototype_bench_sparse_analysis(b, prototype_inline_source(250, true, "\n"))
}

///|
test "PROTOTYPE current code-span index, delimiter-heavy 250 lines" (
  b : @bench.T,
) {
  prototype_bench_current_code_index(
    b,
    prototype_inline_source(250, true, "\n"),
  )
}

///|
test "PROTOTYPE sparse code-span index, delimiter-heavy 250 lines" (
  b : @bench.T,
) {
  prototype_bench_sparse_code_index(b, prototype_inline_source(250, true, "\n"))
}

///|
test "PROTOTYPE current code-span pipeline, delimiter-heavy 250 lines" (
  b : @bench.T,
) {
  prototype_bench_current_code_pipeline(
    b,
    prototype_inline_source(250, true, "\n"),
  )
}

///|
test "PROTOTYPE sparse code-span pipeline, delimiter-heavy 250 lines" (
  b : @bench.T,
) {
  prototype_bench_sparse_code_pipeline(
    b,
    prototype_inline_source(250, true, "\n"),
  )
}

///|
test "PROTOTYPE current link index, delimiter-heavy 250 lines" (b : @bench.T) {
  prototype_bench_current_links(b, prototype_inline_source(250, true, "\n"))
}

///|
test "PROTOTYPE sparse link index, delimiter-heavy 250 lines" (b : @bench.T) {
  prototype_bench_sparse_links(b, prototype_inline_source(250, true, "\n"))
}

///|
test "PROTOTYPE current link pipeline, delimiter-heavy 250 lines" (b : @bench.T) {
  prototype_bench_current_link_pipeline(
    b,
    prototype_inline_source(250, true, "\n"),
  )
}

///|
test "PROTOTYPE sparse link pipeline, delimiter-heavy 250 lines" (b : @bench.T) {
  prototype_bench_sparse_link_pipeline(
    b,
    prototype_inline_source(250, true, "\n"),
  )
}

///|
test "PROTOTYPE current delimiter plan, delimiter-heavy 250 lines" (
  b : @bench.T,
) {
  prototype_bench_current_delimiter_plan(
    b,
    prototype_inline_source(250, true, "\n"),
  )
}

///|
test "PROTOTYPE sparse delimiter plan, delimiter-heavy 250 lines" (b : @bench.T) {
  prototype_bench_sparse_delimiter_plan(
    b,
    prototype_inline_source(250, true, "\n"),
  )
}

///|
test "PROTOTYPE current delimiter pipeline, delimiter-heavy 250 lines" (
  b : @bench.T,
) {
  prototype_bench_current_delimiter_pipeline(
    b,
    prototype_inline_source(250, true, "\n"),
  )
}

///|
test "PROTOTYPE sparse delimiter pipeline, delimiter-heavy 250 lines" (
  b : @bench.T,
) {
  prototype_bench_sparse_delimiter_pipeline(
    b,
    prototype_inline_source(250, true, "\n"),
  )
}

///|
test "PROTOTYPE current parser shell, delimiter-heavy 250 lines" (b : @bench.T) {
  prototype_bench_current_parser_shell(
    b,
    prototype_inline_source(250, true, "\n"),
  )
}

///|
test "PROTOTYPE sparse parser shell, delimiter-heavy 250 lines" (b : @bench.T) {
  prototype_bench_sparse_parser_shell(
    b,
    prototype_inline_source(250, true, "\n"),
  )
}
