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
  mut has_angle_open : Bool
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
  AnalysisAngleOpen
  AnalysisAngleClose
  AnalysisLineBoundary
  AnalysisOther
} derive(Eq)

///|
priv struct InlineAnalysisToken {
  kind : InlineAnalysisTokenKind
  // Borrowed from the parser's immutable source for this analysis pass.
  text : StringView
  start : Int
  end : Int
  first : Char?
  last : Char?
  ends_with_odd_backslashes : Bool
}

///|
priv struct InlineLinkDelimiterIndex {
  candidates : Array[InlineLinkCandidate]
  autolinks : InlineAutolinkIndex?
  bracket_matches : Map[Int, InlineBracketMatch]
  candidate_by_opener : Map[Int, Int]
  candidate_by_suffix : Map[Int, Int]
  candidate_by_label_closer : Map[Int, Int]
  code_conflict_openers : Map[Int, Bool]
  code_conflict_closers : Map[Int, Bool]
  code_conflict_parens : Map[Int, Bool]
}

///|
priv enum InlineLinkSyntacticForm {
  InlineTargetForm
  FullReferenceForm
  CollapsedReferenceForm
}

///|
priv struct InlineBracketFrame {
  index : Int
  code_conflict_generation : Int
}

///|
priv struct InlineBracketMatch {
  closer_index : Int
  code_conflict : Bool
}

///|
priv enum InlineLinkCandidateDisposition {
  ValidLinkDisposition
  LiteralLinkDisposition
}

///|
priv struct InlineLinkCandidate {
  opener_start : Int
  label_closer_start : Int
  suffix_start : Int
  suffix_end : Int
  form : InlineLinkSyntacticForm
  mut disposition : InlineLinkCandidateDisposition
  is_image : Bool
  mut active : Bool
}

///|
priv struct InlineAutolinkCandidate {
  kind : InlineAngleKind
  start : Int
  end : Int
  mut active : Bool
}

///|
priv struct InlineAutolinkIndex {
  // Source-ordered; lookup uses binary search and keeps conflict deactivation
  // local to the candidate array instead of maintaining a parallel hash map.
  candidates : Array[InlineAutolinkCandidate]
}

///|
priv struct InlineLinkLabelFrame {
  candidate_index : Int
  mut contains_qualifying_descendant : Bool
}

///|
fn register_inline_link_candidate(
  links : InlineLinkDelimiterIndex,
  candidate : InlineLinkCandidate,
) -> Unit {
  links.candidates.push(candidate)
}

///|
fn inline_link_candidate_is_image(
  tokens : Array[InlineAnalysisToken],
  opener_index : Int,
) -> Bool {
  guard opener_index > 0 else { return false }
  let previous = tokens[opener_index - 1]
  previous.end == tokens[opener_index].start &&
  previous.last == Some('!') &&
  previous.text.has_suffix("!") &&
  !previous.ends_with_odd_backslashes
}

///|
/// Close one source-nested label frame and propagate whether it contains a
/// valid non-image descendant to its enclosing candidate. The label brackets
/// are matched by the analysis stack, so candidates form properly nested
/// intervals even when destinations contain malformed crossing text.
fn close_inline_link_label_frame(
  links : InlineLinkDelimiterIndex,
  stack : Array[InlineLinkLabelFrame],
  frame : InlineLinkLabelFrame,
) -> Unit {
  let candidate_index = frame.candidate_index
  let candidate = links.candidates[candidate_index]
  if frame.contains_qualifying_descendant &&
    candidate.active &&
    !candidate.is_image {
    links.candidates[candidate_index].disposition = LiteralLinkDisposition
  }
  let finalized = links.candidates[candidate_index]
  let qualifies = finalized.active &&
    !finalized.is_image &&
    finalized.disposition is ValidLinkDisposition
  if frame.contains_qualifying_descendant || qualifies {
    match stack.last() {
      Some(parent) => parent.contains_qualifying_descendant = true
      None => ()
    }
  }
}

///|
/// Select candidates with one source sweep. Destination intervals are
/// converted to start/end coverage deltas so malformed crossing intervals are
/// handled without relying on a nesting assumption. Candidate labels are
/// properly nested, allowing a single stack to propagate valid descendants.
fn finalize_inline_link_candidates(
  links : InlineLinkDelimiterIndex,
  tokens : Array[InlineAnalysisToken],
) -> Unit {
  let destination_starts : Map[Int, Int] = Map([])
  let destination_ends : Map[Int, Int] = Map([])
  for candidate in links.candidates {
    destination_starts[candidate.suffix_start] = destination_starts
      .get(candidate.suffix_start)
      .unwrap_or(0) +
      1
    destination_ends[candidate.suffix_end] = destination_ends
      .get(candidate.suffix_end)
      .unwrap_or(0) +
      1
  }
  let mut destination_coverage = 0
  let mut candidate_cursor = 0
  for token in tokens {
    let offset = token.start
    // A suffix is half-open: an opener at its end is outside the destination,
    // while an opener at its start is inside it.
    destination_coverage = destination_coverage -
      destination_ends.get(offset).unwrap_or(0)
    destination_coverage = destination_coverage +
      destination_starts.get(offset).unwrap_or(0)
    while candidate_cursor < links.candidates.length() &&
          links.candidates[candidate_cursor].opener_start == offset {
      links.candidates[candidate_cursor].active = links.candidates[candidate_cursor].active &&
        destination_coverage == 0
      candidate_cursor = candidate_cursor + 1
    }
  }
  guard candidate_cursor == links.candidates.length() else {
    abort("link candidate opener lies outside its analysis token stream")
  }

  let label_stack : Array[InlineLinkLabelFrame] = []
  for candidate_index = 0
      candidate_index < links.candidates.length()
      candidate_index = candidate_index + 1 {
    let opener = links.candidates[candidate_index].opener_start
    while label_stack.length() > 0 {
      let frame = label_stack.last().unwrap()
      if links.candidates[frame.candidate_index].label_closer_start > opener {
        break
      }
      let closed = label_stack.pop().unwrap()
      close_inline_link_label_frame(links, label_stack, closed)
    }
    label_stack.push({ candidate_index, contains_qualifying_descendant: false })
  }
  while label_stack.pop() is Some(frame) {
    close_inline_link_label_frame(links, label_stack, frame)
  }

  for index = 0; index < links.candidates.length(); index = index + 1 {
    let candidate = links.candidates[index]
    if candidate.active {
      links.candidate_by_opener[candidate.opener_start] = index
      links.candidate_by_suffix[candidate.suffix_start] = index
      links.candidate_by_label_closer[candidate.label_closer_start] = index
    }
  }

  // A code span may make a matched bracket pair literal even though the
  // opener was eventually popped by a visible closer. Defer both endpoint
  // marks until active candidates have claimed their pair; otherwise a later
  // valid link candidate must remain visible to the parser.
  for opener_index, bracket_match in links.bracket_matches {
    if bracket_match.code_conflict {
      let opener_start = tokens[opener_index].start
      let closer_start = tokens[bracket_match.closer_index].start
      if links.candidate_by_opener.get(opener_start) is None {
        links.code_conflict_openers[opener_start] = true
        links.code_conflict_closers[closer_start] = true
      }
    }
  }
}

///|
fn inline_link_candidate_for_opener(
  links : InlineLinkDelimiterIndex,
  opener_start : Int,
) -> InlineLinkCandidate? {
  links.candidate_by_opener
  .get(opener_start)
  .map(index => links.candidates[index])
}

///|
fn inline_link_candidate_for_label_closer(
  links : InlineLinkDelimiterIndex,
  label_closer_start : Int,
) -> InlineLinkCandidate? {
  links.candidate_by_label_closer
  .get(label_closer_start)
  .map(index => links.candidates[index])
}

///|
fn inline_link_candidate_for_suffix(
  links : InlineLinkDelimiterIndex,
  suffix_start : Int,
) -> InlineLinkCandidate? {
  links.candidate_by_suffix
  .get(suffix_start)
  .map(index => links.candidates[index])
}

///|
fn inline_autolink_candidate_index_for_opener(
  autolinks : InlineAutolinkIndex,
  opener_start : Int,
) -> Int? {
  match
    autolinks.candidates[:].binary_search_by(candidate => {
      candidate.start.compare(opener_start)
    }) {
    Ok(index) if autolinks.candidates[index].active => Some(index)
    _ => None
  }
}

///|
fn inline_autolink_candidate_at(
  autolinks : InlineAutolinkIndex,
  opener_start : Int,
) -> InlineAutolinkCandidate? {
  inline_autolink_candidate_index_for_opener(autolinks, opener_start).map(index => {
    autolinks.candidates[index]
  })
}

///|
fn inline_autolink_candidate_for_opener(
  links : InlineLinkDelimiterIndex,
  opener_start : Int,
) -> InlineAutolinkCandidate? {
  links.autolinks.bind(autolinks => {
    inline_autolink_candidate_at(autolinks, opener_start)
  })
}

///|
fn inline_analysis_token_kind(
  token : Token,
  text : StringView,
) -> InlineAnalysisTokenKind {
  match token {
    Star => AnalysisAsterisk
    Underscore => AnalysisUnderscore
    Backtick => AnalysisBacktick
    LeftBracket => AnalysisLeftBracket
    RightBracket => AnalysisRightBracket
    LeftParen => AnalysisLeftParen
    RightParen => AnalysisRightParen
    Text(_) if text == "<" => AnalysisAngleOpen
    Text(_) if text == ">" => AnalysisAngleClose
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
        kind: inline_analysis_token_kind(ctx.peek(), text),
        text,
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
          text: "\n",
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
fn source_view_is_line_ending(view : StringView) -> Bool {
  (
    view.length() == 1 &&
    (
      view.code_unit_at(0).to_int() == 0x0A ||
      view.code_unit_at(0).to_int() == 0x0D
    )
  ) ||
  (
    view.length() == 2 &&
    view.code_unit_at(0).to_int() == 0x0D &&
    view.code_unit_at(1).to_int() == 0x0A
  )
}

///|
/// Return a direct view only when every analysis token is an exact continuation
/// in one backing source. A normalized line-boundary fact is accepted only when
/// its absolute span contains exactly LF, CRLF, or CR; container prefixes make
/// that span wider and deliberately select fallback reconstruction.
fn contiguous_inline_analysis_source(
  tokens : Array[InlineAnalysisToken],
) -> (StringView, Int)? {
  guard tokens.length() > 0 else { return None }
  let first = tokens[0]
  let backing = first.text.data()
  let source_start = first.start
  let mut expected_start = source_start
  for token in tokens {
    guard token.start == expected_start else { return None }
    if token.kind == AnalysisLineBoundary {
      guard source_view_is_line_ending(
        backing.view(start_offset=token.start, end_offset=token.end),
      ) else {
        return None
      }
    } else {
      guard token.text.start_offset() == token.start &&
        token.text.length() == token.end - token.start &&
        physical_equal(token.text.data(), backing) else {
        return None
      }
    }
    expected_start = token.end
  }
  Some(
    (
      backing.view(start_offset=source_start, end_offset=expected_start),
      source_start,
    ),
  )
}

///|
fn index_inline_autolinks(
  tokens : Array[InlineAnalysisToken],
  code_delimiters : CodeSpanDelimiterIndex,
) -> InlineAutolinkIndex {
  let has_exposed_angle = tokens.any(token => token.kind == AnalysisAngleOpen)
  let raw_candidates : Array[InlineAutolinkCandidate] = []
  let contiguous_source = if has_exposed_angle {
    contiguous_inline_analysis_source(tokens)
  } else {
    None
  }
  let logical_starts : Array[Int] = []
  let logical_ends : Array[Int] = []
  let reconstructed_source = if has_exposed_angle && contiguous_source is None {
    let buf = StringBuilder::StringBuilder()
    let mut logical_end = 0
    for token in tokens {
      logical_starts.push(logical_end)
      buf.write_stringview(token.text)
      logical_end = logical_end + token.text.length()
      logical_ends.push(logical_end)
    }
    buf.to_string()
  } else {
    ""
  }
  let source = match contiguous_source {
    Some((view, _)) => view
    None => reconstructed_source.view()
  }
  let delimiter_index = if has_exposed_angle {
    Some(build_inline_angle_delimiter_index(source))
  } else {
    None
  }
  for index, token in tokens {
    let logical_start = match contiguous_source {
      Some((_, source_start)) => token.start - source_start
      None => logical_starts[index]
    }
    let candidate = match token.kind {
      AnalysisAngleOpen =>
        match
          classify_inline_angle_at_with_index(
            source, logical_start, delimiter_index,
          ) {
          Some({ kind, end }) => {
            let absolute_end = match contiguous_source {
              Some((_, source_start)) => Some(source_start + end)
              None =>
                match logical_ends[:].binary_search(end) {
                  Ok(end_index) => Some(tokens[end_index].end)
                  Err(_) => None
                }
            }
            absolute_end.map(absolute_end => {
              (
                { kind, start: token.start, end: absolute_end, active: true } :
                InlineAutolinkCandidate)
            })
          }
          None => None
        }
      _ => None
    }
    match candidate {
      Some(candidate) => raw_candidates.push(candidate)
      None => ()
    }
  }
  let candidates : Array[InlineAutolinkCandidate] = []
  let mut raw_index = 0
  let mut index = 0
  while index < tokens.length() {
    while raw_index < raw_candidates.length() &&
          raw_candidates[raw_index].start < tokens[index].start {
      raw_index = raw_index + 1
    }
    if raw_index < raw_candidates.length() &&
      raw_candidates[raw_index].start == tokens[index].start {
      let candidate = raw_candidates[raw_index]
      raw_index = raw_index + 1
      candidates.push(candidate)
      while index < tokens.length() && tokens[index].end <= candidate.end {
        if tokens[index].kind == AnalysisBacktick {
          code_delimiters.eligible_openers[tokens[index].start] = false
        }
        index = index + 1
      }
    } else {
      match analysis_code_closer_index(tokens, index, code_delimiters) {
        Some(closer) => index = closer + 1
        None => index = index + 1
      }
    }
  }
  { candidates, }
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
priv enum InlineDestinationBoundary {
  Complete(Int)
  Literal(Int)
}

///|
priv struct InlineDestinationFrame {
  opener : Int
  mut prefix_pending : Bool
  mut in_angle : Bool
  mut angle_seen : Bool
  mut angle_line_break : Bool
  mut escaped : Bool
  mut content_seen : Bool
  mut nested_paren_count : Int
  mut has_backtick : Bool
  mut literal_queued : Bool
  mut closed : Bool
}

///|
fn queue_inline_destination_literal_if_eligible(
  frames : Array[InlineDestinationFrame],
  frame_index : Int,
  queued : Array[Int],
) -> Unit {
  let frame = frames[frame_index]
  if !frame.literal_queued &&
    frame.content_seen &&
    frame.prefix_pending == false &&
    (frame.angle_seen || frame.nested_paren_count >= 2) &&
    !frame.has_backtick {
    frame.literal_queued = true
    queued.push(frame_index)
  }
}

///|
/// Index every destination-looking parenthesis with one forward stack pass.
/// The result is local syntax analysis; the persistent candidate arena stores
/// only the selected opener/label/suffix disposition.
fn index_inline_destinations(
  tokens : Array[InlineAnalysisToken],
) -> Map[Int, InlineDestinationBoundary] {
  let boundaries : Map[Int, InlineDestinationBoundary] = Map([])
  let frames : Array[InlineDestinationFrame] = []
  let open_frames : Array[Int] = []
  let queued_frames : Array[Int] = []
  let mut previous_end = 0
  for index = 0; index < tokens.length(); index = index + 1 {
    let token = tokens[index]
    if token.kind == AnalysisLineBoundary {
      match open_frames.last() {
        Some(frame_index) if frames[frame_index].in_angle =>
          frames[frame_index].angle_line_break = true
        _ => ()
      }
      while queued_frames.pop() is Some(frame_index) {
        let frame = frames[frame_index]
        if !frame.closed &&
          frame.content_seen &&
          frame.prefix_pending == false &&
          (frame.angle_seen || frame.nested_paren_count >= 2) &&
          !frame.has_backtick &&
          boundaries.get(frame.opener) is None {
          boundaries[frame.opener] = Literal(previous_end)
        }
      }
      previous_end = token.start
      continue
    }
    previous_end = token.end
    match token.kind {
      AnalysisLeftParen =>
        match open_frames.last() {
          Some(parent_index) if frames[parent_index].in_angle => ()
          Some(parent_index) => {
            let parent = frames[parent_index]
            parent.prefix_pending = false
            parent.content_seen = true
            parent.nested_paren_count = parent.nested_paren_count + 1
            queue_inline_destination_literal_if_eligible(
              frames, parent_index, queued_frames,
            )
            let frame_index = frames.length()
            frames.push({
              opener: index,
              prefix_pending: true,
              in_angle: false,
              angle_seen: false,
              angle_line_break: false,
              escaped: false,
              content_seen: false,
              nested_paren_count: 0,
              has_backtick: false,
              literal_queued: false,
              closed: false,
            })
            open_frames.push(frame_index)
          }
          None => {
            let frame_index = frames.length()
            frames.push({
              opener: index,
              prefix_pending: true,
              in_angle: false,
              angle_seen: false,
              angle_line_break: false,
              escaped: false,
              content_seen: false,
              nested_paren_count: 0,
              has_backtick: false,
              literal_queued: false,
              closed: false,
            })
            open_frames.push(frame_index)
          }
        }
      AnalysisRightParen =>
        match open_frames.last() {
          Some(frame_index) if frames[frame_index].in_angle => ()
          Some(_) =>
            match open_frames.pop() {
              Some(closed_index) => {
                let closed = frames[closed_index]
                closed.closed = true
                boundaries[closed.opener] = if closed.angle_line_break {
                  Literal(token.end)
                } else {
                  Complete(index)
                }
                match open_frames.last() {
                  Some(parent_index) => {
                    let parent = frames[parent_index]
                    let nested_count = closed.nested_paren_count + 1
                    if parent.nested_paren_count < nested_count {
                      parent.nested_paren_count = nested_count
                    }
                    parent.angle_seen = parent.angle_seen || closed.angle_seen
                    parent.has_backtick = parent.has_backtick ||
                      closed.has_backtick
                    queue_inline_destination_literal_if_eligible(
                      frames, parent_index, queued_frames,
                    )
                  }
                  None => ()
                }
              }
              None => ()
            }
          None => ()
        }
      _ =>
        match open_frames.last() {
          Some(frame_index) => {
            let frame = frames[frame_index]
            if token.kind == AnalysisBacktick {
              frame.has_backtick = true
            }
            for ch in token.text {
              if frame.in_angle {
                if ch == '\n' || ch == '\r' {
                  frame.angle_line_break = true
                }
                if frame.escaped {
                  frame.escaped = false
                } else if ch == '\\' {
                  frame.escaped = true
                } else if ch == '>' {
                  frame.in_angle = false
                }
                continue
              }
              if frame.prefix_pending {
                match ch {
                  ' ' | '\t' | '\r' => continue
                  _ => {
                    frame.prefix_pending = false
                    frame.content_seen = true
                    if ch == '<' {
                      frame.in_angle = true
                      frame.angle_seen = true
                    }
                  }
                }
              }
            }
            queue_inline_destination_literal_if_eligible(
              frames, frame_index, queued_frames,
            )
          }
          None => ()
        }
    }
  }
  while queued_frames.pop() is Some(frame_index) {
    let frame = frames[frame_index]
    if !frame.closed &&
      frame.content_seen &&
      frame.prefix_pending == false &&
      (frame.angle_seen || frame.nested_paren_count >= 2) &&
      !frame.has_backtick &&
      boundaries.get(frame.opener) is None {
      boundaries[frame.opener] = Literal(previous_end)
    }
  }
  for frame_index in open_frames {
    let frame = frames[frame_index]
    if frame.content_seen &&
      frame.prefix_pending == false &&
      (frame.angle_seen || frame.nested_paren_count >= 2) &&
      !frame.has_backtick &&
      boundaries.get(frame.opener) is None {
      boundaries[frame.opener] = Literal(previous_end)
    }
  }
  boundaries
}

///|
fn inline_analysis_token_is_spaces(token : InlineAnalysisToken) -> Bool {
  token.kind == AnalysisOther &&
  token.text.length() > 0 &&
  token.text.all(fn(ch) { ch == ' ' || ch == '\t' })
}

///|
fn inline_link_target_disposition(
  tokens : Array[InlineAnalysisToken],
  content_start : Int,
  content_end : Int,
) -> InlineLinkCandidateDisposition {
  let mut first_content = content_start
  while first_content < content_end &&
        inline_analysis_token_is_spaces(tokens[first_content]) {
    first_content = first_content + 1
  }
  guard first_content < content_end && tokens[first_content].first == Some('<') else {
    return ValidLinkDisposition
  }
  let buf = StringBuilder::StringBuilder()
  for index = content_start; index < content_end; index = index + 1 {
    buf.write_stringview(tokens[index].text)
  }
  if parse_inline_link_target(buf.to_string()) is Some(_) {
    ValidLinkDisposition
  } else {
    LiteralLinkDisposition
  }
}

///|
fn index_inline_links(
  tokens : Array[InlineAnalysisToken],
  code_delimiters : CodeSpanDelimiterIndex,
) -> InlineLinkDelimiterIndex {
  let bracket_matches : Map[Int, InlineBracketMatch] = Map([])
  let bracket_stack : Array[InlineBracketFrame] = []
  // A bracket opened before an opaque code span cannot be closed by a right
  // bracket inside that span. Keep this fact in the same indexed authority so
  // the parser can emit the opener literally when no later source closer
  // makes the label valid. A generation records the fact without walking all
  // open brackets for every code span.
  let code_conflict_openers : Map[Int, Bool] = Map([])
  let code_conflict_closers : Map[Int, Bool] = Map([])
  let code_conflict_parens : Map[Int, Bool] = Map([])
  let autolinks = if code_delimiters.has_angle_open {
    Some(index_inline_autolinks(tokens, code_delimiters))
  } else {
    None
  }
  let mut code_conflict_generation = 0
  let mut index = 0
  while index < tokens.length() {
    match analysis_code_closer_index(tokens, index, code_delimiters) {
      Some(closer) => {
        let mut contains_right_bracket = false
        for code_index = index + 1
            code_index < closer
            code_index = code_index + 1 {
          if tokens[code_index].kind == AnalysisRightBracket {
            contains_right_bracket = true
            break
          }
        }
        if contains_right_bracket && bracket_stack.length() > 0 {
          code_conflict_generation = code_conflict_generation + 1
          if closer + 1 < tokens.length() &&
            tokens[closer + 1].kind == AnalysisRightParen {
            code_conflict_parens[tokens[closer + 1].start] = true
          }
        }
        index = closer + 1
      }
      None => {
        match tokens[index].kind {
          AnalysisLineBoundary => ()
          AnalysisLeftBracket =>
            bracket_stack.push({ index, code_conflict_generation })
          AnalysisRightBracket =>
            match bracket_stack.pop() {
              Some(opener) => {
                let code_conflict = opener.code_conflict_generation <
                  code_conflict_generation
                bracket_matches[opener.index] = {
                  closer_index: index,
                  code_conflict,
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
  for opener in bracket_stack {
    if opener.code_conflict_generation < code_conflict_generation {
      code_conflict_openers[tokens[opener.index].start] = true
    }
  }
  let destination_boundaries = index_inline_destinations(tokens)
  let links : InlineLinkDelimiterIndex = {
    candidates: [],
    autolinks,
    bracket_matches,
    candidate_by_opener: Map([]),
    candidate_by_suffix: Map([]),
    candidate_by_label_closer: Map([]),
    code_conflict_openers,
    code_conflict_closers,
    code_conflict_parens,
  }
  index = 0
  while index < tokens.length() {
    match analysis_code_closer_index(tokens, index, code_delimiters) {
      Some(closer) => index = closer + 1
      None => {
        match tokens[index].kind {
          AnalysisLeftBracket =>
            match links.bracket_matches.get(index) {
              Some(label_match) => {
                let label_closer = label_match.closer_index
                let after_label = label_closer + 1
                if after_label < tokens.length() &&
                  tokens[after_label].kind == AnalysisLeftParen {
                  match destination_boundaries.get(after_label) {
                    Some(Complete(destination_end)) =>
                      register_inline_link_candidate(links, {
                        opener_start: tokens[index].start,
                        label_closer_start: tokens[label_closer].start,
                        suffix_start: tokens[after_label].start,
                        suffix_end: tokens[destination_end].end,
                        form: InlineTargetForm,
                        disposition: inline_link_target_disposition(
                          tokens,
                          after_label + 1,
                          destination_end,
                        ),
                        is_image: inline_link_candidate_is_image(tokens, index),
                        active: true,
                      })
                    Some(Literal(literal_end)) =>
                      register_inline_link_candidate(links, {
                        opener_start: tokens[index].start,
                        label_closer_start: tokens[label_closer].start,
                        suffix_start: tokens[after_label].start,
                        suffix_end: literal_end,
                        form: InlineTargetForm,
                        disposition: LiteralLinkDisposition,
                        is_image: inline_link_candidate_is_image(tokens, index),
                        active: true,
                      })
                    None => ()
                  }
                } else if after_label < tokens.length() &&
                  tokens[after_label].kind == AnalysisLeftBracket &&
                  links.bracket_matches.get(after_label)
                  is Some(reference_match) {
                  let reference_closer = reference_match.closer_index
                  let form = if reference_closer == after_label + 1 {
                    CollapsedReferenceForm
                  } else {
                    FullReferenceForm
                  }
                  register_inline_link_candidate(links, {
                    opener_start: tokens[index].start,
                    label_closer_start: tokens[label_closer].start,
                    suffix_start: tokens[after_label].start,
                    suffix_end: tokens[reference_closer].end,
                    form,
                    disposition: ValidLinkDisposition,
                    is_image: inline_link_candidate_is_image(tokens, index),
                    active: true,
                  })
                } else {
                  let mut separated = after_label
                  while separated < tokens.length() &&
                        inline_analysis_token_is_spaces(tokens[separated]) {
                    separated = separated + 1
                  }
                  if separated > after_label &&
                    separated < tokens.length() &&
                    tokens[separated].kind == AnalysisLeftParen {
                    match destination_boundaries.get(separated) {
                      Some(boundary) => {
                        let suffix_end = match boundary {
                          Complete(destination_end) =>
                            tokens[destination_end].end
                          Literal(destination_end) => destination_end
                        }
                        register_inline_link_candidate(links, {
                          opener_start: tokens[index].start,
                          label_closer_start: tokens[label_closer].start,
                          suffix_start: tokens[separated].start,
                          suffix_end,
                          form: InlineTargetForm,
                          disposition: LiteralLinkDisposition,
                          is_image: inline_link_candidate_is_image(
                            tokens, index,
                          ),
                          active: true,
                        })
                      }
                      None => ()
                    }
                  }
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
  resolve_inline_autolink_link_conflicts(links, tokens)
  finalize_inline_link_candidates(links, tokens)
  links
}

///|
fn mark_inline_link_candidate_literal_boundaries(
  links : InlineLinkDelimiterIndex,
  candidate : InlineLinkCandidate,
) -> Unit {
  links.code_conflict_openers[candidate.opener_start] = true
  links.code_conflict_closers[candidate.label_closer_start] = true
  match candidate.form {
    InlineTargetForm => {
      links.code_conflict_parens[candidate.suffix_start] = true
      links.code_conflict_parens[candidate.suffix_end - 1] = true
    }
    FullReferenceForm | CollapsedReferenceForm => {
      links.code_conflict_openers[candidate.suffix_start] = true
      links.code_conflict_closers[candidate.suffix_end - 1] = true
    }
  }
}

///|
fn resolve_inline_autolink_link_conflicts(
  links : InlineLinkDelimiterIndex,
  tokens : Array[InlineAnalysisToken],
) -> Unit {
  guard links.autolinks is Some(autolinks) else { return }
  guard links.candidates.length() > 0 else { return }
  let destination_starts : Map[Int, Int] = Map([])
  let destination_ends : Map[Int, Int] = Map([])
  let literal_destination_starts : Map[Int, Int] = Map([])
  let literal_destination_ends : Map[Int, Int] = Map([])
  let candidate_by_opener : Map[Int, Int] = Map([])
  let candidate_by_label_closer : Map[Int, Int] = Map([])
  for index, candidate in links.candidates {
    match candidate.disposition {
      ValidLinkDisposition => {
        destination_starts[candidate.suffix_start] = destination_starts
          .get(candidate.suffix_start)
          .unwrap_or(0) +
          1
        destination_ends[candidate.suffix_end] = destination_ends
          .get(candidate.suffix_end)
          .unwrap_or(0) +
          1
      }
      LiteralLinkDisposition => {
        literal_destination_starts[candidate.suffix_start] = literal_destination_starts
          .get(candidate.suffix_start)
          .unwrap_or(0) +
          1
        literal_destination_ends[candidate.suffix_end] = literal_destination_ends
          .get(candidate.suffix_end)
          .unwrap_or(0) +
          1
      }
    }
    candidate_by_opener[candidate.opener_start] = index
    candidate_by_label_closer[candidate.label_closer_start] = index
  }
  let label_stack : Array[Int] = []
  let mut destination_coverage = 0
  let mut literal_destination_coverage = 0
  for token in tokens {
    let offset = token.start
    destination_coverage = destination_coverage -
      destination_ends.get(offset).unwrap_or(0)
    destination_coverage = destination_coverage +
      destination_starts.get(offset).unwrap_or(0)
    literal_destination_coverage = literal_destination_coverage -
      literal_destination_ends.get(offset).unwrap_or(0)
    literal_destination_coverage = literal_destination_coverage +
      literal_destination_starts.get(offset).unwrap_or(0)
    match candidate_by_opener.get(offset) {
      Some(index) => label_stack.push(index)
      None => ()
    }
    match inline_autolink_candidate_index_for_opener(autolinks, offset) {
      Some(autolink_index) => {
        let autolink = autolinks.candidates[autolink_index]
        if destination_coverage > 0 ||
          (
            literal_destination_coverage > 0 &&
            !(autolink.kind is InlineHtmlAngle)
          ) {
          autolinks.candidates[autolink_index].active = false
        } else {
          for stack_index = label_stack.length() - 1
              stack_index >= 0
              stack_index = stack_index - 1 {
            let link_index = label_stack[stack_index]
            let link = links.candidates[link_index]
            // All candidates enter `active`; this break only fires for links
            // already deactivated by an earlier autolink in this same pass,
            // so every remaining ancestor is inactive too.
            if !link.active {
              break
            }
            if autolink.kind is InlineHtmlAngle &&
              autolink.end <= link.label_closer_start {
              // Inline HTML may nest in eligible link or image label content.
              break
            }
            if autolink.end <= link.label_closer_start && link.is_image {
              break
            }
            link.active = false
            mark_inline_link_candidate_literal_boundaries(links, link)
          }
        }
      }
      None => ()
    }
    match candidate_by_label_closer.get(offset) {
      Some(index) =>
        match label_stack.pop() {
          Some(open_index) if open_index == index => ()
          _ => abort("link label stack lost source nesting")
        }
      None => ()
    }
  }
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
    match inline_autolink_candidate_for_opener(links, tokens[index].start) {
      Some(candidate) => {
        events.push(
          OpaqueInlineEvent(
            DelimiterSourceRange(candidate.start, candidate.end),
          ),
        )
        while index < tokens.length() && tokens[index].end < candidate.end {
          index = index + 1
        }
        guard index < tokens.length() && tokens[index].end == candidate.end else {
          abort("autolink candidate range points outside its inline container")
        }
        previous_char = Some('>')
        index = index + 1
        continue
      }
      None => ()
    }
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
        match inline_link_candidate_for_suffix(links, tokens[index].start) {
          Some(candidate) => {
            let suffix_end = candidate.suffix_end
            let start = tokens[index].start
            while index < tokens.length() && tokens[index].end < suffix_end {
              index = index + 1
            }
            guard index < tokens.length() && tokens[index].end == suffix_end else {
              abort("link candidate range points outside its inline container")
            }
            events.push(
              OpaqueInlineEvent(DelimiterSourceRange(start, suffix_end)),
            )
            previous_char = match candidate.form {
              InlineTargetForm => Some(')')
              FullReferenceForm | CollapsedReferenceForm => Some(']')
            }
            index = index + 1
          }
          None => {
            if inline_link_candidate_for_opener(links, tokens[index].start)
              is Some(_) {
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
                if inline_link_candidate_for_label_closer(
                    links,
                    tokens[index].start,
                  )
                  is Some(_) {
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
    has_angle_open: false,
  }
  let previous_by_length : Map[Int, Int] = Map([])
  let mut preceding_text_ends_escaped = false
  for token in tokens {
    if token.kind == AnalysisAngleOpen {
      index.has_angle_open = true
    }
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
fn parse_indexed_inline_autolink(
  ctx : @core.ParserContext[Token, SyntaxKind],
  candidate : InlineAutolinkCandidate,
  continue_line : () -> Bool,
) -> Unit {
  guard ctx.current_token_range().start == candidate.start else {
    abort("indexed autolink did not reach its opening angle")
  }
  let kind = match candidate.kind {
    InlineAngleKind::UriAutolink => UriAutolinkNode
    InlineAngleKind::EmailAutolink => EmailAutolinkNode
    InlineAngleKind::InlineHtmlAngle => InlineHtmlNode
  }
  ctx.start_node(kind)
  while ctx.current_token_range().start < candidate.end {
    if ctx.peek() is Newline {
      guard continue_line() else {
        abort("indexed angle candidate crossed its inline container boundary")
      }
    } else {
      guard !is_inline_end(ctx.peek()) else {
        abort("indexed angle candidate crossed its inline container boundary")
      }
      ctx.emit_current_token()
    }
  }
  guard ctx.current_token_range().start == candidate.end else {
    abort("indexed autolink did not end on a lexer token boundary")
  }
  ctx.finish_node()
}

///|
fn parse_indexed_inline_angles_in_literal_line(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
) -> Unit {
  let analysis_tokens = ctx.lookahead(() => {
    collect_inline_analysis_tokens(ctx, policy, () => false)
  })
  let delimiters = build_code_span_delimiter_index(analysis_tokens)
  let angles = if delimiters.has_angle_open {
    Some(index_inline_autolinks(analysis_tokens, delimiters))
  } else {
    None
  }
  while !token_is_inline_end(ctx.peek(), policy) {
    let candidate = match angles {
      Some(angles) =>
        inline_autolink_candidate_at(angles, ctx.current_token_range().start)
      None => None
    }
    match candidate {
      Some(candidate) =>
        parse_indexed_inline_autolink(ctx, candidate, () => false)
      None => ctx.emit_token(TextToken)
    }
  }
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
  match
    inline_autolink_candidate_for_opener(links, ctx.current_token_range().start) {
    Some(candidate) => {
      parse_indexed_inline_autolink(ctx, candidate, continue_line)
      return
    }
    None => ()
  }
  match ctx.peek() {
    Star | StarStar | Underscore => ctx.emit_token(TextToken)
    Backtick => parse_indexed_inline_code(ctx, delimiters, continue_line)
    LeftParen | RightParen if links.code_conflict_parens
      .get(ctx.current_token_range().start)
      .unwrap_or(false) => ctx.emit_token(TextToken)
    RightBracket if links.code_conflict_closers
      .get(ctx.current_token_range().start)
      .unwrap_or(false) => ctx.emit_token(TextToken)
    LeftBracket => {
      let opener_start = ctx.current_token_range().start
      if inline_link_candidate_for_opener(links, opener_start) is Some(_) {
        parse_link(
          ctx, policy, delimiters, links, delimiter_cursor, continue_line,
        )
      } else if links.code_conflict_openers.get(opener_start).unwrap_or(false) {
        // The code-span index has already made the crossing link boundary
        // literal. Do not manufacture recovery for a bracket that code owns.
        ctx.emit_token(TextToken)
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
  let opener_start = ctx.current_token_range().start
  guard inline_link_candidate_for_opener(links, opener_start) is Some(candidate) else {
    abort("parse_link requires a pre-indexed confirmed link")
  }
  let label_closer_start = candidate.label_closer_start
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
        match
          inline_link_candidate_for_opener(
            links,
            ctx.current_token_range().start,
          ) {
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
  match candidate.form {
    InlineTargetForm =>
      match candidate.disposition {
        ValidLinkDisposition => {
          guard ctx.peek() is LeftParen else {
            abort("pre-indexed link label did not reach its destination")
          }
          guard ctx.current_token_range().start == candidate.suffix_start else {
            abort("pre-indexed link label did not reach its destination start")
          }
          ctx.emit_token(LeftParenToken)
          // The analysis pass is the single owner of destination balancing.
          while !token_is_inline_block_boundary(ctx.peek(), policy) &&
                ctx.current_token_range().end < candidate.suffix_end {
            match ctx.peek() {
              Newline => {
                guard continue_line() else {
                  abort(
                    "indexed link destination crossed its container boundary",
                  )
                }
              }
              LeftParen => ctx.emit_token(LeftParenToken)
              RightParen => ctx.emit_token(RightParenToken)
              Text(_) => ctx.emit_token(TextToken)
              Indentation(_) => ctx.emit_token(TextToken)
              Star | StarStar | Underscore => ctx.emit_token(TextToken)
              Backtick => ctx.emit_token(BacktickToken)
              LeftBracket => ctx.emit_token(LeftBracketToken)
              RightBracket => ctx.emit_token(RightBracketToken)
              _ => ctx.bump_error()
            }
          }
          guard !is_inline_end(ctx.peek()) &&
            ctx.current_token_range().end == candidate.suffix_end &&
            ctx.peek() is RightParen else {
            abort(
              "pre-indexed link destination did not reach its closing parenthesis",
            )
          }
          ctx.emit_token(RightParenToken)
        }
        LiteralLinkDisposition => {
          // Keep a malformed-but-bounded candidate in one LinkNode envelope.
          // Every token in the arena range is typed TextToken; lowering can
          // then preserve typed inline HTML atoms without recovery Raw nodes.
          while !token_is_inline_block_boundary(ctx.peek(), policy) &&
                ctx.current_token_range().start < candidate.suffix_start {
            if ctx.peek() is Newline {
              guard continue_line() else {
                abort("literal link suffix crossed its container boundary")
              }
            } else {
              ctx.emit_token(TextToken)
            }
          }
          guard ctx.current_token_range().start == candidate.suffix_start else {
            abort("pre-indexed literal link did not reach its suffix start")
          }
          while ctx.current_token_range().start < candidate.suffix_end {
            match
              inline_autolink_candidate_for_opener(
                links,
                ctx.current_token_range().start,
              ) {
              Some(angle) if angle.kind is InlineHtmlAngle =>
                parse_indexed_inline_autolink(ctx, angle, continue_line)
              _ =>
                if ctx.peek() is Newline {
                  guard continue_line() else {
                    abort(
                      "literal link destination crossed its container boundary",
                    )
                  }
                } else {
                  match ctx.peek() {
                    Text(_)
                    | Indentation(_)
                    | Star
                    | StarStar
                    | Underscore
                    | Backtick
                    | LeftBracket
                    | RightBracket
                    | LeftParen
                    | RightParen => ctx.emit_token(TextToken)
                    OrderedListMarker(_) if policy.allows_ordered_marker() =>
                      ctx.emit_token(TextToken)
                    _ => ctx.bump_error()
                  }
                }
            }
          }
          guard ctx.current_token_range().start == candidate.suffix_end else {
            abort(
              "pre-indexed literal link did not reach its bounded destination",
            )
          }
        }
      }
    FullReferenceForm | CollapsedReferenceForm => {
      guard ctx.peek() is LeftBracket else {
        abort("pre-indexed reference link did not reach its reference label")
      }
      guard ctx.current_token_range().start == candidate.suffix_start else {
        abort("pre-indexed reference link did not reach its reference start")
      }
      let literal_suffix = candidate.disposition is LiteralLinkDisposition
      if literal_suffix {
        ctx.emit_token(TextToken)
      } else {
        ctx.emit_token(LeftBracketToken)
      }
      while !token_is_inline_block_boundary(ctx.peek(), policy) &&
            ctx.current_token_range().end < candidate.suffix_end {
        if ctx.peek() is Newline {
          guard continue_line() else {
            abort("indexed reference label crossed its container boundary")
          }
        } else if literal_suffix {
          ctx.emit_token(TextToken)
        } else {
          match ctx.peek() {
            LeftBracket => ctx.emit_token(LeftBracketToken)
            RightBracket => ctx.emit_token(RightBracketToken)
            Backtick => ctx.emit_token(BacktickToken)
            _ => ctx.emit_token(TextToken)
          }
        }
      }
      guard !token_is_inline_block_boundary(ctx.peek(), policy) &&
        ctx.current_token_range().end == candidate.suffix_end &&
        ctx.peek() is RightBracket else {
        abort("pre-indexed reference label did not reach its closing bracket")
      }
      if literal_suffix {
        ctx.emit_token(TextToken)
      } else {
        ctx.emit_token(RightBracketToken)
      }
    }
  }
  ctx.finish_node()
}
