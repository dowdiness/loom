// PROTOTYPE — THROWAWAY. Keep this package off main.
//
// Question: can one container-local, source-faithful plan represent code spans,
// angle constructs, links/images, and emphasis as properly nested or disjoint
// ranges while mapping logical offsets back to discontinuous absolute source
// segments in deterministic linear work?
//
// The core is pure. The sibling native TUI is only an imperative shell.

///|
priv struct PrototypeRange {
  start : Int
  end : Int
}

///|
priv struct SourceSegment {
  logical : PrototypeRange
  absolute : PrototypeRange
  text : String
}

///|
priv struct BoundaryEvidence {
  original : Set[Int]
  admissible : Set[Int]
  work_units : Int
}

///|
priv enum CandidateKind {
  CodeCandidate
  UriAngleCandidate
  EmailAngleCandidate
  HtmlAngleCandidate
  LinkCandidate
  ImageCandidate
  EmphasisCandidate
} derive(Eq)

///|
fn CandidateKind::label(self : CandidateKind) -> String {
  match self {
    CodeCandidate => "code"
    UriAngleCandidate => "uri-angle"
    EmailAngleCandidate => "email-angle"
    HtmlAngleCandidate => "html-angle"
    LinkCandidate => "link"
    ImageCandidate => "image"
    EmphasisCandidate => "emphasis"
  }
}

///|
fn CandidateKind::is_angle(self : CandidateKind) -> Bool {
  match self {
    UriAngleCandidate | EmailAngleCandidate | HtmlAngleCandidate => true
    _ => false
  }
}

///|
priv struct Candidate {
  kind : CandidateKind
  range : PrototypeRange
  label : PrototypeRange?
  suffix : PrototypeRange?
}

///|
priv struct CandidateDecision {
  candidate : Candidate
  mut selected : Bool
  mut reason : String
}

///|
priv struct WorkCount {
  mut source_units : Int
  mut candidate_units : Int
  mut ordering_units : Int
  mut resolver_steps : Int
  mut mapping_steps : Int
}

///|
priv struct PlanInvariants {
  source_round_trip : Bool
  expected_selection : Bool
  selected_nested_or_disjoint : Bool
  selected_token_aligned : Bool
  work_linear_bound : Bool
}

///|
priv struct PrototypeScenario {
  id : String
  title : String
  source : String
  content_ranges : Array[PrototypeRange]
  expectation : String
  expected_selected : String
  expected_rejected : String
  verify_expected : Bool
}

///|
priv struct PrototypeReport {
  scenario : PrototypeScenario
  view : String
  segments : Array[SourceSegment]
  absolute_before : Array[Int]
  absolute_after : Array[Int]
  original_boundaries : Set[Int]
  proposed_boundaries : Set[Int]
  decisions : Array[CandidateDecision]
  invariants : PlanInvariants
  work : WorkCount
}

///|
fn PrototypeScenario::id(self : PrototypeScenario) -> String {
  self.id
}

///|
fn PrototypeScenario::title(self : PrototypeScenario) -> String {
  self.title
}

///|
fn whole_source_scenario(
  id : String,
  title : String,
  source : String,
  expectation : String,
  expected_selected : String,
  expected_rejected : String,
) -> PrototypeScenario {
  {
    id,
    title,
    source,
    content_ranges: [{ start: 0, end: source.length() }],
    expectation,
    expected_selected,
    expected_rejected,
    verify_expected: true,
  }
}

///|
fn continuation_scenario(newline : String, id : String) -> PrototypeScenario {
  let first = "> <span title=\"a" + newline
  let second = "> b\">x</span>" + newline
  let source = first + second
  let first_content_start = 2
  let first_content_end = first.length()
  let second_content_start = first.length() + 2
  let second_content_end = source.length() - newline.length()
  let newline_name = match newline {
    "\n" => "LF"
    "\r\n" => "CRLF"
    _ => "CR"
  }
  {
    id,
    title: "container continuation preserves " + newline_name,
    source,
    content_ranges: [
      { start: first_content_start, end: first_content_end },
      { start: second_content_start, end: second_content_end },
    ],
    expectation: "opening and closing HTML candidates; the opening range maps across the prefix gap",
    expected_selected: "html-angle,html-angle",
    expected_rejected: "",
    verify_expected: true,
  }
}

///|
fn prototype_scenarios() -> ReadOnlyArray[PrototypeScenario] {
  ReadOnlyArray::from_array([
    whole_source_scenario(
      "cm-342", "CommonMark 342 — crossing code rejects link", "[not a `link](/foo`)\n",
      "code selected; crossing link rejected", "code", "link",
    ),
    whole_source_scenario(
      "cm-343", "CommonMark 343 — code crosses inline HTML", "`<a href=\"`\">`\n",
      "code selected; crossing HTML candidate rejected", "code", "html-angle",
    ),
    whole_source_scenario(
      "cm-344", "CommonMark 344 — inline HTML owns unmatched backtick", "<a href=\"`\">`\n",
      "HTML angle selected; trailing unmatched backtick remains literal", "html-angle",
      "code",
    ),
    whole_source_scenario(
      "cm-345", "CommonMark 345 — code crosses URI autolink", "`<https://foo.bar.`baz>`\n",
      "code selected; crossing URI angle rejected", "code", "uri-angle",
    ),
    whole_source_scenario(
      "cm-346", "CommonMark 346 — URI autolink owns unmatched backtick", "<https://foo.bar.`baz>`\n",
      "URI angle selected; trailing unmatched backtick remains literal", "uri-angle",
      "code",
    ),
    whole_source_scenario(
      "cm-516", "CommonMark 516 — code and emphasis nest in link label", "[link *foo **bar** `#`*](/uri)\n",
      "link, code, and emphasis remain properly nested", "link,emphasis,emphasis,code",
      "",
    ),
    whole_source_scenario(
      "cm-525", "CommonMark 525 — crossing code rejects link", "[foo`](/uri)`\n",
      "code selected; crossing link rejected", "code", "link",
    ),
    whole_source_scenario(
      "cm-526", "CommonMark 526 — autolink rejects crossing outer link", "[foo<https://example.com/?search=](uri)>\n",
      "URI angle selected; crossing link rejected", "uri-angle", "link",
    ),
    whole_source_scenario(
      "destination-backticks", "matching backticks inside link destination", "[x](foo`bar`)\n",
      "link selected; destination-owned backticks are not code", "link", "code",
    ),
    whole_source_scenario(
      "title-backticks", "matching backticks inside link title", "[x](url \"`title`\")\n",
      "link selected; title-owned backticks are not code", "link", "code",
    ),
    continuation_scenario("\n", "continuation-lf"),
    continuation_scenario("\r\n", "continuation-crlf"),
    continuation_scenario("\r", "continuation-cr"),
    whole_source_scenario(
      "angle-free", "angle-free ordinary prose", "plain source with no inline delimiter candidates\n",
      "zero selected candidates and no angle-specific source scan", "", "",
    ),
  ])
}

///|
fn source_slice(source : String, range : PrototypeRange) -> String {
  source[range.start:range.end].to_owned()
}

///|
fn build_source_view(
  scenario : PrototypeScenario,
  work : WorkCount,
) -> (String, Array[SourceSegment], Bool) {
  let out = StringBuilder::new()
  let segments : Array[SourceSegment] = []
  let mut logical_start = 0
  let mut previous_end = 0
  let mut valid = true
  for range in scenario.content_ranges {
    work.mapping_steps += 1
    if range.start < previous_end ||
      range.start < 0 ||
      range.end < range.start ||
      range.end > scenario.source.length() {
      valid = false
    } else {
      let text = source_slice(scenario.source, range)
      out.write_string(text)
      let logical_end = logical_start + text.length()
      segments.push({
        logical: { start: logical_start, end: logical_end },
        absolute: range,
        text,
      })
      logical_start = logical_end
      previous_end = range.end
      work.source_units += 2 * text.length()
    }
  }
  let view = out.to_string()
  let reconstructed = StringBuilder::new()
  for segment in segments {
    work.mapping_steps += segment.text.length() + 1
    reconstructed.write_string(segment.text)
  }
  (view, segments, valid && reconstructed.to_string() == view)
}

///|
fn count_run(
  source : String,
  start : Int,
  marker : UInt16,
  work : WorkCount,
) -> Int {
  for index = start; index < source.length(); index = index + 1 {
    work.candidate_units += 1
    if source[index] != marker {
      return index - start
    }
  }
  source.length() - start
}

///|
fn discover_code_candidates(
  source : String,
  candidates : Array[Candidate],
  work : WorkCount,
) -> Unit {
  let pending : Map[Int, Int] = Map([])
  for index = 0; index < source.length(); {
    work.candidate_units += 1
    if source[index] == '`' {
      let length = count_run(source, index, '`', work)
      match pending.get(length) {
        Some(opener) => {
          candidates.push({
            kind: CodeCandidate,
            range: { start: opener, end: index + length },
            label: None,
            suffix: None,
          })
          pending.remove(length)
        }
        None => pending[length] = index
      }
      continue index + length
    }
    continue index + 1
  }
}

///|
fn next_marker_indexes(
  source : String,
  marker : UInt16,
  work : WorkCount,
) -> Array[Int] {
  let nearest = Array::make(source.length(), -1)
  let mut next = -1
  for index = source.length() - 1; index >= 0; index = index - 1 {
    nearest[index] = next
    if source[index] == marker {
      next = index
    }
    work.candidate_units += 1
  }
  nearest
}

///|
fn angle_kind(content : StringView) -> CandidateKind? {
  if content.has_prefix("http://") || content.has_prefix("https://") {
    Some(UriAngleCandidate)
  } else if content.contains("@") &&
    !content.contains(" ") &&
    !content.contains("\n") &&
    !content.contains("\r") {
    Some(EmailAngleCandidate)
  } else if content.length() > 0 &&
    (
      content[0] == '/' ||
      content[0] == '!' ||
      content[0] == '?' ||
      (content[0] >= 'A' && content[0] <= 'Z') ||
      (content[0] >= 'a' && content[0] <= 'z')
    ) {
    Some(HtmlAngleCandidate)
  } else {
    None
  }
}

///|
fn discover_angle_candidates(
  source : String,
  candidates : Array[Candidate],
  work : WorkCount,
) -> Unit {
  let next_closer = next_marker_indexes(source, '>', work)
  let next_opener = next_marker_indexes(source, '<', work)
  for index = 0; index < source.length(); index = index + 1 {
    work.candidate_units += 1
    if source[index] == '<' && next_closer[index] >= 0 {
      let closer = next_closer[index]
      if next_opener[index] >= 0 && next_opener[index] < closer {
        continue
      }
      let content = source[index + 1:closer]
      work.candidate_units += 4 * content.length()
      match angle_kind(content) {
        Some(kind) =>
          candidates.push({
            kind,
            range: { start: index, end: closer + 1 },
            label: None,
            suffix: None,
          })
        None => ()
      }
    }
  }
}

///|
fn discover_link_candidates(
  source : String,
  candidates : Array[Candidate],
  work : WorkCount,
) -> Unit {
  let next_paren_closer = next_marker_indexes(source, ')', work)
  let openers : Array[Int] = []
  for index = 0; index < source.length(); index = index + 1 {
    work.candidate_units += 1
    match source[index] {
      '[' => openers.push(index)
      ']' =>
        match openers.pop() {
          Some(opener) if index + 1 < source.length() &&
            source[index + 1] == '(' &&
            next_paren_closer[index + 1] >= 0 => {
            let suffix_end = next_paren_closer[index + 1]
            let is_image = opener > 0 && source[opener - 1] == '!'
            candidates.push({
              kind: if is_image {
                ImageCandidate
              } else {
                LinkCandidate
              },
              range: {
                start: if is_image {
                  opener - 1
                } else {
                  opener
                },
                end: suffix_end + 1,
              },
              label: Some({ start: opener + 1, end: index }),
              suffix: Some({ start: index + 1, end: suffix_end + 1 }),
            })
          }
          _ => ()
        }
      _ => ()
    }
  }
}

///|
fn discover_emphasis_candidates(
  source : String,
  candidates : Array[Candidate],
  work : WorkCount,
) -> Unit {
  let pending : Map[String, (Int, Int)] = Map([])
  for index = 0; index < source.length(); {
    work.candidate_units += 1
    if source[index] == '*' || source[index] == '_' {
      let marker = source[index]
      let length = count_run(source, index, marker, work)
      let key = "\{marker}:\{length}"
      match pending.get(key) {
        Some((opener, opener_length)) => {
          candidates.push({
            kind: EmphasisCandidate,
            range: { start: opener, end: index + length },
            label: None,
            suffix: None,
          })
          pending.remove(key)
          ignore(opener_length)
        }
        None => pending[key] = (index, length)
      }
      continue index + length
    }
    continue index + 1
  }
}

///|
fn discover_candidates(source : String, work : WorkCount) -> Array[Candidate] {
  let candidates : Array[Candidate] = []
  discover_code_candidates(source, candidates, work)
  discover_angle_candidates(source, candidates, work)
  discover_link_candidates(source, candidates, work)
  discover_emphasis_candidates(source, candidates, work)
  candidates
}

///|
fn order_candidates(
  candidates : Array[Candidate],
  source_length : Int,
  work : WorkCount,
) -> Array[Candidate] {
  let by_start : Map[Int, Array[Candidate]] = Map([])
  for candidate in candidates {
    work.ordering_units += 1
    let bucket = by_start.get_or_init(candidate.range.start, () => [])
    bucket.push(candidate)
  }
  let ordered : Array[Candidate] = []
  for start = 0; start <= source_length; start = start + 1 {
    work.ordering_units += 1
    match by_start.get(start) {
      Some(bucket) => {
        bucket.sort_by((left, right) => {
          work.ordering_units += 1
          let by_end = right.range.end - left.range.end
          if by_end != 0 {
            by_end
          } else {
            left.kind.label().compare(right.kind.label())
          }
        })
        for candidate in bucket {
          work.ordering_units += 1
          ordered.push(candidate)
        }
      }
      None => ()
    }
  }
  ordered
}

///|
fn range_contains(outer : PrototypeRange, inner : PrototypeRange) -> Bool {
  outer.start <= inner.start && inner.end <= outer.end
}

///|
fn range_is_inside(range : PrototypeRange, owner : PrototypeRange?) -> Bool {
  match owner {
    Some(owner) => range_contains(owner, range)
    None => false
  }
}

///|
priv enum ParentConflict {
  KeepNested
  RejectParent(String)
  RejectCurrent(String)
}

///|
fn resolve_contained_candidate(
  parent : Candidate,
  current : Candidate,
) -> ParentConflict {
  match parent.kind {
    CodeCandidate => RejectCurrent("inside opaque code span")
    UriAngleCandidate | EmailAngleCandidate | HtmlAngleCandidate =>
      RejectCurrent("inside owned angle candidate")
    LinkCandidate | ImageCandidate =>
      if range_is_inside(current.range, parent.suffix) {
        RejectCurrent("inside link/image destination or title")
      } else if range_is_inside(current.range, parent.label) {
        if parent.kind == LinkCandidate &&
          (current.kind.is_angle() || current.kind == LinkCandidate) {
          RejectParent("nested link-like candidate owns the label")
        } else {
          KeepNested
        }
      } else {
        RejectParent("candidate crosses link label/suffix ownership")
      }
    EmphasisCandidate => KeepNested
  }
}

///|
fn resolve_crossing_candidate(
  parent : Candidate,
  current : Candidate,
) -> ParentConflict {
  match current.kind {
    CodeCandidate =>
      if parent.kind.is_angle() {
        RejectCurrent("code opener is owned by the angle candidate")
      } else {
        RejectParent("crossing code span has precedence")
      }
    UriAngleCandidate | EmailAngleCandidate | HtmlAngleCandidate =>
      match parent.kind {
        CodeCandidate => RejectCurrent("crosses an owning code span")
        _ => RejectParent("crossing angle candidate owns its complete range")
      }
    LinkCandidate | ImageCandidate =>
      match parent.kind {
        CodeCandidate
        | UriAngleCandidate
        | EmailAngleCandidate
        | HtmlAngleCandidate => RejectCurrent("crosses an opaque owner")
        _ => RejectParent("link/image boundary closes the active scope")
      }
    EmphasisCandidate => RejectCurrent("emphasis may not cross an owner")
  }
}

///|
fn resolve_plan(
  ordered : Array[Candidate],
  work : WorkCount,
) -> Array[CandidateDecision] {
  let decisions = ordered.map(candidate => {
    candidate,
    selected: true,
    reason: "selected",
  })
  work.resolver_steps += decisions.length()
  let active : Array[Int] = []
  for current_index = 0
      current_index < decisions.length()
      current_index = current_index + 1 {
    let current = decisions[current_index].candidate
    while active.last() is Some(parent_index) &&
          decisions[parent_index].candidate.range.end <= current.range.start {
      ignore(active.pop())
      work.resolver_steps += 1
    }
    let mut keep_current = true
    while keep_current && active.last() is Some(parent_index) {
      work.resolver_steps += 1
      let parent = decisions[parent_index].candidate
      let outcome = if current.range.end <= parent.range.end {
        resolve_contained_candidate(parent, current)
      } else {
        resolve_crossing_candidate(parent, current)
      }
      match outcome {
        KeepNested => break
        RejectCurrent(reason) => {
          decisions[current_index].selected = false
          decisions[current_index].reason = reason
          keep_current = false
        }
        RejectParent(reason) => {
          decisions[parent_index].selected = false
          decisions[parent_index].reason = reason
          ignore(active.pop())
        }
      }
    }
    if keep_current {
      active.push(current_index)
    }
  }
  decisions
}

///|
fn decision_signature(
  decisions : Array[CandidateDecision],
  selected : Bool,
  work : WorkCount,
) -> String {
  let labels : Array[String] = []
  for decision in decisions {
    work.resolver_steps += 1
    if decision.selected == selected {
      labels.push(decision.candidate.kind.label())
    }
  }
  labels.join(",")
}

///|
fn selected_ranges_are_nested_or_disjoint(
  decisions : Array[CandidateDecision],
  work : WorkCount,
) -> Bool {
  let active : Array[PrototypeRange] = []
  for decision in decisions {
    if decision.selected {
      let current = decision.candidate.range
      while active.last() is Some(parent) && parent.end <= current.start {
        ignore(active.pop())
        work.resolver_steps += 1
      }
      work.resolver_steps += 1
      match active.last() {
        Some(parent) if current.end > parent.end => return false
        _ => active.push(current)
      }
    }
  }
  true
}

///|
fn production_absolute_boundaries(source : String) -> BoundaryEvidence raise {
  let original : Set[Int] = Set::Set([0])
  let admissible : Set[Int] = Set::Set([0])
  let mut offset = 0
  let mut work_units = 0
  for info in @markdown.tokenize(source) {
    work_units += 1
    let start = offset
    offset += info.len
    original.add(offset)
    admissible.add(offset)
    match info.token {
      @markdown.Text(_) =>
        for absolute = start; absolute < offset; absolute = absolute + 1 {
          work_units += 1
          match source[absolute] {
            '<' | '>' | '`' => {
              admissible.add(absolute)
              admissible.add(absolute + 1)
            }
            _ => ()
          }
        }
      _ => ()
    }
  }
  { original, admissible, work_units }
}

///|
fn logical_boundaries(
  view : String,
  segments : Array[SourceSegment],
  absolute_boundaries : BoundaryEvidence,
  work : WorkCount,
) -> (Set[Int], Set[Int]) {
  let original : Set[Int] = Set::Set([0, view.length()])
  let proposed : Set[Int] = Set::Set([0, view.length()])
  for segment in segments {
    for logical = segment.logical.start
        logical <= segment.logical.end
        logical = logical + 1 {
      work.mapping_steps += 1
      let absolute = segment.absolute.start + logical - segment.logical.start
      if absolute_boundaries.original.contains(absolute) {
        original.add(logical)
      }
      if absolute_boundaries.admissible.contains(absolute) {
        proposed.add(logical)
      }
    }
  }
  (original, proposed)
}

///|
fn logical_absolute_boundaries(
  view_length : Int,
  segments : Array[SourceSegment],
  work : WorkCount,
) -> (Array[Int], Array[Int]) {
  let before = Array::make(view_length + 1, -1)
  let after = Array::make(view_length + 1, -1)
  for segment in segments {
    for logical = segment.logical.start
        logical <= segment.logical.end
        logical = logical + 1 {
      work.mapping_steps += 1
      let absolute = segment.absolute.start + logical - segment.logical.start
      if logical == segment.logical.start {
        after[logical] = absolute
        if before[logical] < 0 {
          before[logical] = absolute
        }
      } else if logical == segment.logical.end {
        before[logical] = absolute
        if after[logical] < 0 {
          after[logical] = absolute
        }
      } else {
        before[logical] = absolute
        after[logical] = absolute
      }
    }
  }
  (before, after)
}

///|
fn selected_ranges_are_aligned(
  decisions : Array[CandidateDecision],
  boundaries : Set[Int],
  work : WorkCount,
) -> Bool {
  for decision in decisions {
    work.resolver_steps += 1
    if decision.selected &&
      (
        !boundaries.contains(decision.candidate.range.start) ||
        !boundaries.contains(decision.candidate.range.end)
      ) {
      return false
    }
  }
  true
}

///|
fn analyze_without_lexer(
  scenario : PrototypeScenario,
  absolute_boundaries : BoundaryEvidence,
) -> PrototypeReport {
  let work : WorkCount = {
    source_units: 0,
    candidate_units: 0,
    ordering_units: 0,
    resolver_steps: 0,
    mapping_steps: absolute_boundaries.work_units,
  }
  let (view, segments, source_round_trip) = build_source_view(scenario, work)
  let candidates = discover_candidates(view, work)
  let ordered = order_candidates(candidates, view.length(), work)
  let decisions = resolve_plan(ordered, work)
  let (absolute_before, absolute_after) = logical_absolute_boundaries(
    view.length(),
    segments,
    work,
  )
  let (original_boundaries, proposed_boundaries) = logical_boundaries(
    view, segments, absolute_boundaries, work,
  )
  let selected_nested_or_disjoint = selected_ranges_are_nested_or_disjoint(
    decisions, work,
  )
  let selected_token_aligned = selected_ranges_are_aligned(
    decisions, proposed_boundaries, work,
  )
  let expected_selection = !scenario.verify_expected ||
    (
      decision_signature(decisions, true, work) == scenario.expected_selected &&
      decision_signature(decisions, false, work) == scenario.expected_rejected
    )
  let total_work = work.source_units +
    work.candidate_units +
    work.ordering_units +
    work.resolver_steps +
    work.mapping_steps
  // Fixed-pass accounting budget, not a wall-time performance threshold.
  let linear_pass_budget = 24
  let linear_limit = linear_pass_budget *
    (view.length() + decisions.length() + 1)
  {
    scenario,
    view,
    segments,
    absolute_before,
    absolute_after,
    original_boundaries,
    proposed_boundaries,
    decisions,
    invariants: {
      source_round_trip,
      expected_selection,
      selected_nested_or_disjoint,
      selected_token_aligned,
      work_linear_bound: total_work <= linear_limit,
    },
    work,
  }
}

///|
fn analyze_prototype_scenario(
  scenario : PrototypeScenario,
) -> PrototypeReport raise {
  analyze_without_lexer(
    scenario,
    production_absolute_boundaries(scenario.source),
  )
}

///|
fn PrototypeReport::passed(self : PrototypeReport) -> Bool {
  self.invariants.source_round_trip &&
  self.invariants.expected_selection &&
  self.invariants.selected_nested_or_disjoint &&
  self.invariants.selected_token_aligned &&
  self.invariants.work_linear_bound
}

///|
fn escaped_source(source : String) -> String {
  source
  .replace_all(old="\r", new="\\r")
  .replace_all(old="\n", new="\\n")
  .replace_all(old="\t", new="\\t")
}

///|
fn range_text(range : PrototypeRange) -> String {
  "[\{range.start},\{range.end})"
}

///|
fn render_prototype_report(report : PrototypeReport) -> String {
  let out = StringBuilder::new()
  out.write_string("QUESTION\n")
  out.write_string(
    "  Can one source-faithful container plan stay nested/disjoint and linear?\n\n",
  )
  out.write_string("SCENARIO\n")
  out.write_string("  id: " + report.scenario.id + "\n")
  out.write_string("  title: " + report.scenario.title + "\n")
  out.write_string("  expected: " + report.scenario.expectation + "\n")
  out.write_string("  source: " + escaped_source(report.scenario.source) + "\n")
  out.write_string("  logical view: " + escaped_source(report.view) + "\n\n")
  out.write_string("SOURCE SEGMENTS (logical -> absolute)\n")
  for segment in report.segments {
    out.write_string(
      "  " +
      range_text(segment.logical) +
      " -> " +
      range_text(segment.absolute) +
      "  \"" +
      escaped_source(segment.text) +
      "\"\n",
    )
  }
  out.write_string("\nPLAN DECISIONS\n")
  if report.decisions.length() == 0 {
    out.write_string("  (none)\n")
  }
  for decision in report.decisions {
    let candidate = decision.candidate
    let absolute_start = report.absolute_after[candidate.range.start]
    let absolute_end = report.absolute_before[candidate.range.end]
    let crosses_gap = absolute_end - absolute_start !=
      candidate.range.end - candidate.range.start
    out.write_string(
      "  " +
      (if decision.selected { "SELECT " } else { "REJECT " }) +
      candidate.kind.label() +
      " logical=" +
      range_text(candidate.range) +
      " absolute-endpoints=" +
      range_text({ start: absolute_start, end: absolute_end }) +
      (if crosses_gap { " gap-aware" } else { "" }) +
      " — " +
      decision.reason +
      "\n",
    )
  }
  out.write_string("\nBOUNDARIES\n")
  out.write_string(
    "  production=" +
    report.original_boundaries.length().to_string() +
    " proposed=" +
    report.proposed_boundaries.length().to_string() +
    "\n",
  )
  out.write_string("\nINVARIANTS\n")
  out.write_string(
    "  source round-trip: " +
    report.invariants.source_round_trip.to_string() +
    "\n",
  )
  out.write_string(
    "  expected selection: " +
    report.invariants.expected_selection.to_string() +
    "\n",
  )
  out.write_string(
    "  selected nested/disjoint: " +
    report.invariants.selected_nested_or_disjoint.to_string() +
    "\n",
  )
  out.write_string(
    "  selected token-aligned: " +
    report.invariants.selected_token_aligned.to_string() +
    "\n",
  )
  out.write_string(
    "  bounded linear work: " +
    report.invariants.work_linear_bound.to_string() +
    "\n",
  )
  out.write_string("\nWORK COUNTS\n")
  out.write_string("  source units: \{report.work.source_units}\n")
  out.write_string("  candidate units: \{report.work.candidate_units}\n")
  out.write_string("  ordering units: \{report.work.ordering_units}\n")
  out.write_string("  resolver steps: \{report.work.resolver_steps}\n")
  out.write_string("  mapping steps: \{report.work.mapping_steps}\n")
  out.write_string(
    "\nVERDICT: " + (if report.passed() { "GO" } else { "STOP" }) + "\n",
  )
  out.to_string()
}

///|
fn repeated_source(motif : String, count : Int) -> String {
  let out = StringBuilder::new(size_hint=motif.length() * count)
  for _ in 0..<count {
    out.write_string(motif)
  }
  out.to_string()
}

///|
fn stress_scenario(kind : String, count : Int) -> PrototypeScenario {
  let source = match kind {
    "angle" => repeated_source("<https://e.test/`x`> ", count)
    "greater" => repeated_source("ordinary > prose > only ", count)
    "unclosed-angle" => repeated_source("<", count)
    "shared-angle-closer" => repeated_source("<", count) + "a>"
    "unclosed-link" => repeated_source("[", count)
    _ => repeated_source("ordinary prose without delimiters ", count)
  }
  {
    id: "stress-" + kind + "-" + count.to_string(),
    title: kind + " stress at " + count.to_string(),
    source,
    content_ranges: [{ start: 0, end: source.length() }],
    expectation: "operation count scales linearly",
    expected_selected: "",
    expected_rejected: "",
    verify_expected: false,
  }
}

///|
fn segmented_stress_scenario(count : Int) -> PrototypeScenario {
  let source = StringBuilder::new()
  let ranges : Array[PrototypeRange] = []
  let mut absolute = 0
  for _ in 0..<count {
    source.write_string("> ")
    absolute += 2
    let start = absolute
    source.write_string("<a>\n")
    absolute += 4
    ranges.push({ start, end: absolute })
  }
  {
    id: "stress-segmented-" + count.to_string(),
    title: "segmented stress at " + count.to_string(),
    source: source.to_string(),
    content_ranges: ranges,
    expectation: "candidate and segment counts scale together",
    expected_selected: "",
    expected_rejected: "",
    verify_expected: false,
  }
}

///|
fn boundary_evidence_or_abort(source : String) -> BoundaryEvidence {
  try production_absolute_boundaries(source) catch {
    _ => abort("prototype production tokenization failed")
  } noraise {
    evidence => evidence
  }
}

///|
pub fn prototype_stress_report() -> String {
  let out = StringBuilder::new()
  out.write_string("DETERMINISTIC WORK SCALING\n")
  for
    kind in [
      "plain", "greater", "angle", "unclosed-angle", "shared-angle-closer", "unclosed-link",
      "segmented",
    ] {
    out.write_string("\n" + kind + "\n")
    for count in [16, 64, 256, 1024] {
      let scenario = if kind == "segmented" {
        segmented_stress_scenario(count)
      } else {
        stress_scenario(kind, count)
      }
      let report = analyze_without_lexer(
        scenario,
        boundary_evidence_or_abort(scenario.source),
      )
      let total = report.work.source_units +
        report.work.candidate_units +
        report.work.ordering_units +
        report.work.resolver_steps +
        report.work.mapping_steps
      out.write_string(
        "  n=" +
        count.to_string() +
        " bytes=" +
        report.view.length().to_string() +
        " work=" +
        total.to_string() +
        " ratio=" +
        (total / (report.view.length() + 1)).to_string() +
        " pass=" +
        report.passed().to_string() +
        "\n",
      )
    }
  }
  out.to_string()
}

///|
pub fn prototype_scenario_count() -> Int {
  prototype_scenarios().length()
}

///|
pub fn prototype_render_scenario(index : Int) -> String raise {
  guard prototype_scenarios().get(index) is Some(scenario) else {
    fail("prototype scenario index out of range")
  }
  render_prototype_report(analyze_prototype_scenario(scenario))
}

///|
pub fn prototype_all_summary() -> String raise {
  let out = StringBuilder::new()
  out.write_string("ALL SCENARIO VERDICTS\n\n")
  for scenario in prototype_scenarios() {
    let report = analyze_prototype_scenario(scenario)
    out.write_string(
      (if report.passed() { "GO   " } else { "STOP " }) +
      scenario.id() +
      " — " +
      scenario.title() +
      "\n",
    )
  }
  out.to_string()
}
