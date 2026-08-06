// CommonMark emphasis delimiter resolution.
//
// This module is deliberately private to the Markdown package. It accepts
// parser-local facts and returns source ranges; it does not depend on CST,
// MarkdownIR, or editor projection types. The parser shell must omit facts
// from opaque inline regions such as code spans and link destinations.
// Moon does not count whitebox tests for production reachability, so the
// staged shell-facing declarations suppress only their local unused warnings.

///|
#warnings("-unused_constructor")
priv enum EmphasisDelimiterMarker {
  AsteriskDelimiter
  UnderscoreDelimiter
} derive(Eq, Debug)

///|
#warnings("-unused_constructor")
priv enum DelimiterNeighbor {
  DelimiterWhitespace
  DelimiterPunctuationOrSymbol
  DelimiterOther
} derive(Eq)

///|
priv struct DelimiterRunFact {
  marker : EmphasisDelimiterMarker
  start : Int
  length : Int
  can_open : Bool
  can_close : Bool
}

///|
#warnings("-unused_constructor")
priv enum DelimiterResolverEvent {
  DelimiterRunEvent(DelimiterRunFact)
  // Emitted only after the parser has confirmed a link or image. Resolution
  // above this bottom cannot consume an outer delimiter run.
  PushLinkLabelScope
  ResolveLinkLabelScope
  // Code spans, link destinations, and other opaque inline constructs advance
  // source order without contributing delimiter runs.
  OpaqueInlineEvent(DelimiterSourceRange)
}

///|
priv enum ResolvedEmphasisKind {
  ResolvedEmphasis
  ResolvedStrong
} derive(Eq, Debug)

///|
// Half-open UTF-16 source offsets, matching Loom's CST range convention.
priv struct DelimiterSourceRange(Int, Int) derive(Eq, Debug)

///|
#warnings("-unused_value")
priv enum DelimiterPlanEvent {
  OpenEmphasisDelimiter(ResolvedEmphasisKind, DelimiterSourceRange)
  CloseEmphasisDelimiter(ResolvedEmphasisKind, DelimiterSourceRange)
  LiteralEmphasisDelimiter(EmphasisDelimiterMarker, DelimiterSourceRange)
} derive(Eq, Debug)

///|
#warnings("-unused_field")
priv struct DelimiterResolutionPlan {
  // This source-ordered stream is the sole semantic result. Consumers derive
  // any pairing view from its balanced open/close events instead of storing a
  // second representation.
  events : ReadOnlyArray[DelimiterPlanEvent]
  stats : DelimiterResolutionStats
}

///|
#warnings("-unused_field")
priv struct DelimiterResolutionStats {
  run_count : Int
  opener_checks : Int
}

///|
priv struct WorkingDelimiterRun {
  fact : DelimiterRunFact
  mut remaining : Int
  mut opener_used : Int
  mut closer_used : Int
  mut previous : Int
  mut next : Int
  mut active : Bool
  opener_events : Array[DelimiterPlanEvent]
  closer_events : Array[DelimiterPlanEvent]
}

///|
priv struct DelimiterResolverState {
  runs : Array[WorkingDelimiterRun]
  mut top : Int
  mut opener_checks : Int
}

///|
#warnings("-unused_value")
// `escaped` represents one marker consumed by a backslash, not a raw marker
// run. The parser shell emits any immediately adjacent unescaped suffix as a
// separate delimiter-run fact so it remains eligible for emphasis.
fn delimiter_run_fact(
  marker : EmphasisDelimiterMarker,
  start : Int,
  length : Int,
  before : DelimiterNeighbor,
  after : DelimiterNeighbor,
  escaped~ : Bool,
) -> DelimiterRunFact {
  guard !escaped || length == 1 else {
    abort("escaped delimiter facts must contain exactly one marker")
  }
  let left_flanking = after != DelimiterWhitespace &&
    (
      after != DelimiterPunctuationOrSymbol ||
      before == DelimiterWhitespace ||
      before == DelimiterPunctuationOrSymbol
    )
  let right_flanking = before != DelimiterWhitespace &&
    (
      before != DelimiterPunctuationOrSymbol ||
      after == DelimiterWhitespace ||
      after == DelimiterPunctuationOrSymbol
    )
  let (can_open, can_close) = if escaped {
    (false, false)
  } else {
    match marker {
      AsteriskDelimiter => (left_flanking, right_flanking)
      UnderscoreDelimiter =>
        (
          left_flanking &&
          (!right_flanking || before == DelimiterPunctuationOrSymbol),
          right_flanking &&
          (!left_flanking || after == DelimiterPunctuationOrSymbol),
        )
    }
  }
  { marker, start, length, can_open, can_close }
}

///|
fn delimiter_runs_form_odd_match(
  opener : DelimiterRunFact,
  closer : DelimiterRunFact,
) -> Bool {
  (closer.can_open || opener.can_close) &&
  closer.length % 3 != 0 &&
  (opener.length + closer.length) % 3 == 0
}

///|
fn build_delimiter_plan_events(
  runs : Array[WorkingDelimiterRun],
) -> Array[DelimiterPlanEvent] {
  let events : Array[DelimiterPlanEvent] = []
  for run in runs {
    for event in run.closer_events {
      events.push(event)
    }
    let literal_start = run.fact.start + run.closer_used
    let literal_end = run.fact.start + run.fact.length - run.opener_used
    if literal_start < literal_end {
      events.push(
        LiteralEmphasisDelimiter(
          run.fact.marker,
          DelimiterSourceRange(literal_start, literal_end),
        ),
      )
    }
    for i = run.opener_events.length() - 1; i >= 0; i = i - 1 {
      events.push(run.opener_events[i])
    }
  }
  events
}

///|
fn DelimiterResolverState::push_run(
  self : DelimiterResolverState,
  fact : DelimiterRunFact,
) -> Unit {
  let active = fact.can_open || fact.can_close
  let index = self.runs.length()
  let previous = if active { self.top } else { -1 }
  self.runs.push({
    fact,
    remaining: fact.length,
    opener_used: 0,
    closer_used: 0,
    previous,
    next: -1,
    active,
    opener_events: [],
    closer_events: [],
  })
  if active {
    if previous >= 0 {
      self.runs[previous].next = index
    }
    self.top = index
  }
}

///|
fn DelimiterResolverState::remove_run(
  self : DelimiterResolverState,
  index : Int,
) -> Unit {
  guard self.runs[index].active else { return }
  let previous = self.runs[index].previous
  let next = self.runs[index].next
  if previous >= 0 {
    self.runs[previous].next = next
  }
  if next >= 0 {
    self.runs[next].previous = previous
  } else {
    self.top = previous
  }
  self.runs[index].active = false
}

///|
fn DelimiterResolverState::remove_between(
  self : DelimiterResolverState,
  opener : Int,
  closer : Int,
) -> Unit {
  let mut current = self.runs[opener].next
  while current != closer {
    let next = self.runs[current].next
    self.remove_run(current)
    current = next
  }
}

///|
fn delimiter_openers_bottom_index(fact : DelimiterRunFact) -> Int {
  let marker_offset = match fact.marker {
    AsteriskDelimiter => 0
    UnderscoreDelimiter => 6
  }
  marker_offset + (if fact.can_open { 3 } else { 0 }) + fact.length % 3
}

///|
fn DelimiterResolverState::first_above(
  self : DelimiterResolverState,
  bottom : Int,
) -> Int {
  if bottom >= 0 {
    self.runs[bottom].next
  } else {
    let mut first = self.top
    while first >= 0 && self.runs[first].previous >= 0 {
      first = self.runs[first].previous
    }
    first
  }
}

///|
fn DelimiterResolverState::record_match(
  self : DelimiterResolverState,
  opener : Int,
  closer : Int,
) -> Unit {
  let width = if self.runs[opener].remaining >= 2 &&
    self.runs[closer].remaining >= 2 {
    2
  } else {
    1
  }
  let opener_end = self.runs[opener].fact.start +
    self.runs[opener].fact.length -
    self.runs[opener].opener_used
  let closer_start = self.runs[closer].fact.start +
    self.runs[closer].closer_used
  let kind = if width == 2 { ResolvedStrong } else { ResolvedEmphasis }
  let opener_range = DelimiterSourceRange(opener_end - width, opener_end)
  let closer_range = DelimiterSourceRange(closer_start, closer_start + width)
  self.runs[opener].opener_events.push(
    OpenEmphasisDelimiter(kind, opener_range),
  )
  self.runs[closer].closer_events.push(
    CloseEmphasisDelimiter(kind, closer_range),
  )
  self.runs[opener].remaining = self.runs[opener].remaining - width
  self.runs[opener].opener_used = self.runs[opener].opener_used + width
  self.runs[closer].remaining = self.runs[closer].remaining - width
  self.runs[closer].closer_used = self.runs[closer].closer_used + width
}

///|
fn DelimiterResolverState::process_above(
  self : DelimiterResolverState,
  bottom : Int,
) -> Unit {
  let openers_bottom = Array::make(12, bottom)
  let mut closer = self.first_above(bottom)
  while closer >= 0 {
    if !self.runs[closer].fact.can_close {
      closer = self.runs[closer].next
      continue
    }
    let bucket = delimiter_openers_bottom_index(self.runs[closer].fact)
    let lower_bound = openers_bottom[bucket]
    let mut opener = self.runs[closer].previous
    while opener > lower_bound {
      self.opener_checks += 1
      if self.runs[opener].fact.marker == self.runs[closer].fact.marker &&
        self.runs[opener].fact.can_open &&
        !delimiter_runs_form_odd_match(
          self.runs[opener].fact,
          self.runs[closer].fact,
        ) {
        break
      }
      opener = self.runs[opener].previous
    }
    if opener > lower_bound {
      self.record_match(opener, closer)
      self.remove_between(opener, closer)
      if self.runs[opener].remaining == 0 {
        self.remove_run(opener)
      }
      if self.runs[closer].remaining == 0 {
        let next = self.runs[closer].next
        self.remove_run(closer)
        closer = next
      }
    } else {
      let old_closer = closer
      let next = self.runs[old_closer].next
      openers_bottom[bucket] = self.runs[old_closer].previous
      if !self.runs[old_closer].fact.can_open {
        self.remove_run(old_closer)
      }
      closer = next
    }
  }
  let mut current = self.top
  while current != bottom && current >= 0 {
    let previous = self.runs[current].previous
    self.remove_run(current)
    current = previous
  }
}

///|
fn resolve_delimiter_event_state(
  events : Array[DelimiterResolverEvent],
) -> DelimiterResolverState {
  let state : DelimiterResolverState = { runs: [], top: -1, opener_checks: 0 }
  let scope_bottoms : Array[Int] = []
  let mut previous_event_end = 0
  for event in events {
    match event {
      DelimiterRunEvent(fact) => {
        guard fact.start >= previous_event_end && fact.length > 0 else {
          abort("delimiter runs must be positive, ordered, and non-overlapping")
        }
        previous_event_end = fact.start + fact.length
        state.push_run(fact)
      }
      PushLinkLabelScope => scope_bottoms.push(state.top)
      ResolveLinkLabelScope =>
        match scope_bottoms.pop() {
          Some(bottom) => state.process_above(bottom)
          None => abort("delimiter scope end without a matching start")
        }
      OpaqueInlineEvent(DelimiterSourceRange(start, end)) => {
        guard start >= previous_event_end && end > start else {
          abort(
            "opaque inline ranges must be positive, ordered, and non-overlapping",
          )
        }
        previous_event_end = end
      }
    }
  }
  guard scope_bottoms.length() == 0 else {
    abort("delimiter scope start without a matching end")
  }
  state.process_above(-1)
  state
}

///|
fn build_delimiter_resolution_plan(
  state : DelimiterResolverState,
) -> DelimiterResolutionPlan {
  let plan_events = build_delimiter_plan_events(state.runs)
  {
    events: ReadOnlyArray::from_array(plan_events),
    stats: {
      run_count: state.runs.length(),
      opener_checks: state.opener_checks,
    },
  }
}

///|
#warnings("-unused_value")
fn resolve_delimiter_events(
  events : Array[DelimiterResolverEvent],
) -> DelimiterResolutionPlan {
  build_delimiter_resolution_plan(resolve_delimiter_event_state(events))
}
