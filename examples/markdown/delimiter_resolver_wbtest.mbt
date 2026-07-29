///|
fn delimiter_test_run(
  marker : EmphasisDelimiterMarker,
  start : Int,
  length : Int,
  before : DelimiterNeighbor,
  after : DelimiterNeighbor,
  escaped? : Bool = false,
) -> DelimiterResolverEvent {
  DelimiterRunEvent(
    delimiter_run_fact(marker, start, length, before, after, escaped~),
  )
}

///|
fn delimiter_test_fact(
  marker : EmphasisDelimiterMarker,
  start : Int,
  length : Int,
  can_open : Bool,
  can_close : Bool,
) -> DelimiterResolverEvent {
  DelimiterRunEvent({ marker, start, length, can_open, can_close })
}

///|
test "delimiter facts: CommonMark flanking covers Unicode punctuation and symbols" {
  let facts = [
    delimiter_run_fact(
      AsteriskDelimiter,
      0,
      1,
      DelimiterWhitespace,
      DelimiterOther,
      escaped=false,
    ),
    delimiter_run_fact(
      AsteriskDelimiter,
      1,
      1,
      DelimiterOther,
      DelimiterWhitespace,
      escaped=false,
    ),
    delimiter_run_fact(
      AsteriskDelimiter,
      2,
      1,
      DelimiterOther,
      DelimiterOther,
      escaped=false,
    ),
    delimiter_run_fact(
      AsteriskDelimiter,
      3,
      1,
      DelimiterWhitespace,
      DelimiterWhitespace,
      escaped=false,
    ),
    // The shell classifies Unicode P/S scalars such as em dash, £, and €
    // into this category before constructing the pure resolver fact.
    delimiter_run_fact(
      AsteriskDelimiter,
      4,
      1,
      DelimiterPunctuationOrSymbol,
      DelimiterOther,
      escaped=false,
    ),
    delimiter_run_fact(
      AsteriskDelimiter,
      5,
      1,
      DelimiterOther,
      DelimiterPunctuationOrSymbol,
      escaped=false,
    ),
    delimiter_run_fact(
      UnderscoreDelimiter,
      6,
      1,
      DelimiterOther,
      DelimiterOther,
      escaped=false,
    ),
    delimiter_run_fact(
      UnderscoreDelimiter,
      7,
      1,
      DelimiterWhitespace,
      DelimiterOther,
      escaped=false,
    ),
    delimiter_run_fact(
      UnderscoreDelimiter,
      8,
      1,
      DelimiterOther,
      DelimiterWhitespace,
      escaped=false,
    ),
    delimiter_run_fact(
      UnderscoreDelimiter,
      9,
      1,
      DelimiterPunctuationOrSymbol,
      DelimiterPunctuationOrSymbol,
      escaped=false,
    ),
    delimiter_run_fact(
      AsteriskDelimiter,
      10,
      1,
      DelimiterWhitespace,
      DelimiterOther,
      escaped=true,
    ),
  ]
  assert_eq(facts.map(fn(fact) { (fact.can_open, fact.can_close) }), [
    (true, false),
    (false, true),
    (true, true),
    (false, false),
    (true, false),
    (false, true),
    (false, false),
    (true, false),
    (false, true),
    (true, true),
    (false, false),
  ])
}

///|
test "panic delimiter facts: escaped facts contain one marker" {
  ignore(
    delimiter_run_fact(
      AsteriskDelimiter,
      0,
      2,
      DelimiterWhitespace,
      DelimiterPunctuationOrSymbol,
      escaped=true,
    ),
  )
}

///|
test "delimiter resolver: underscores resolve normally but stay literal intraword" {
  let emphasis = resolve_delimiter_events([
    delimiter_test_fact(UnderscoreDelimiter, 0, 1, true, false),
    delimiter_test_fact(UnderscoreDelimiter, 4, 1, false, true),
  ])
  assert_eq(emphasis.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(0, 1)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(4, 5)),
  ])
  let intraword = resolve_delimiter_events([
    delimiter_test_fact(UnderscoreDelimiter, 3, 1, false, false),
    delimiter_test_fact(UnderscoreDelimiter, 7, 1, false, false),
  ])
  assert_eq(intraword.events.iter().to_array(), [
    LiteralEmphasisDelimiter(UnderscoreDelimiter, DelimiterSourceRange(3, 4)),
    LiteralEmphasisDelimiter(UnderscoreDelimiter, DelimiterSourceRange(7, 8)),
  ])
}

///|
test "delimiter resolver: resolves asterisks into emphasis" {
  let plan = resolve_delimiter_events([
    delimiter_test_run(
      AsteriskDelimiter,
      0,
      1,
      DelimiterWhitespace,
      DelimiterOther,
    ),
    delimiter_test_run(
      AsteriskDelimiter,
      4,
      1,
      DelimiterOther,
      DelimiterWhitespace,
    ),
  ])
  assert_eq(plan.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(0, 1)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(4, 5)),
  ])
}

///|
test "delimiter resolver: CommonMark 412 keeps the interior double run literal" {
  let plan = resolve_delimiter_events([
    delimiter_test_run(
      AsteriskDelimiter,
      0,
      1,
      DelimiterWhitespace,
      DelimiterOther,
    ),
    delimiter_test_run(AsteriskDelimiter, 4, 2, DelimiterOther, DelimiterOther),
    delimiter_test_run(
      AsteriskDelimiter,
      9,
      1,
      DelimiterOther,
      DelimiterWhitespace,
    ),
  ])
  assert_eq(plan.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(0, 1)),
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(4, 6)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(9, 10)),
  ])
}

///|
test "delimiter resolver: partial runs preserve opener prefix and closer suffix" {
  let opener_residual = resolve_delimiter_events([
    delimiter_test_fact(AsteriskDelimiter, 0, 2, true, false),
    delimiter_test_fact(AsteriskDelimiter, 5, 1, false, true),
  ])
  assert_eq(opener_residual.events.iter().to_array(), [
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(0, 1)),
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(1, 2)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(5, 6)),
  ])
  let closer_residual = resolve_delimiter_events([
    delimiter_test_fact(AsteriskDelimiter, 0, 1, true, false),
    delimiter_test_fact(AsteriskDelimiter, 4, 2, false, true),
  ])
  assert_eq(closer_residual.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(0, 1)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(4, 5)),
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(5, 6)),
  ])
}

///|
test "delimiter resolver: multiple-of-three permits two divisible runs" {
  let plan = resolve_delimiter_events([
    delimiter_test_fact(AsteriskDelimiter, 3, 3, true, true),
    delimiter_test_fact(AsteriskDelimiter, 9, 3, true, true),
  ])
  assert_eq(plan.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(3, 4)),
    OpenEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(4, 6)),
    CloseEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(9, 11)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(11, 12)),
  ])
}

///|
test "delimiter resolver: a dual-purpose run can close, stay literal, and open" {
  let plan = resolve_delimiter_events([
    delimiter_test_fact(AsteriskDelimiter, 0, 1, true, false),
    delimiter_test_fact(AsteriskDelimiter, 4, 3, true, true),
    delimiter_test_fact(AsteriskDelimiter, 10, 1, false, true),
  ])
  assert_eq(plan.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(0, 1)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(4, 5)),
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(5, 6)),
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(6, 7)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(10, 11)),
  ])
}

///|
test "delimiter resolver: CommonMark 467 consumes triple runs from the inside out" {
  let plan = resolve_delimiter_events([
    delimiter_test_run(
      AsteriskDelimiter,
      0,
      3,
      DelimiterWhitespace,
      DelimiterOther,
    ),
    delimiter_test_run(
      AsteriskDelimiter,
      6,
      3,
      DelimiterOther,
      DelimiterWhitespace,
    ),
  ])
  assert_eq(plan.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(0, 1)),
    OpenEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(1, 3)),
    CloseEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(6, 8)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(8, 9)),
  ])
}

///|
test "delimiter resolver: repeated consumption leaves the exact literal suffix" {
  let plan = resolve_delimiter_events([
    delimiter_test_fact(AsteriskDelimiter, 3, 6, true, true),
    delimiter_test_fact(AsteriskDelimiter, 12, 9, true, true),
  ])
  assert_eq(plan.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(3, 5)),
    OpenEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(5, 7)),
    OpenEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(7, 9)),
    CloseEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(12, 14)),
    CloseEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(14, 16)),
    CloseEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(16, 18)),
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(18, 21)),
  ])
}

///|
test "delimiter resolver: mixed markers resolve without crossing" {
  let plan = resolve_delimiter_events([
    delimiter_test_fact(AsteriskDelimiter, 0, 1, true, false),
    delimiter_test_fact(UnderscoreDelimiter, 5, 1, true, false),
    delimiter_test_fact(AsteriskDelimiter, 9, 1, false, true),
    delimiter_test_fact(UnderscoreDelimiter, 14, 1, false, true),
  ])
  assert_eq(plan.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(0, 1)),
    LiteralEmphasisDelimiter(UnderscoreDelimiter, DelimiterSourceRange(5, 6)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(9, 10)),
    LiteralEmphasisDelimiter(UnderscoreDelimiter, DelimiterSourceRange(14, 15)),
  ])
}

///|
test "delimiter resolver: a closer selects the nearest eligible opener" {
  let plan = resolve_delimiter_events([
    delimiter_test_fact(AsteriskDelimiter, 0, 2, true, false),
    delimiter_test_fact(AsteriskDelimiter, 6, 2, true, false),
    delimiter_test_fact(AsteriskDelimiter, 15, 2, false, true),
  ])
  assert_eq(plan.events.iter().to_array(), [
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(0, 2)),
    OpenEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(6, 8)),
    CloseEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(15, 17)),
  ])
}

///|
test "delimiter resolver: odd escapes are literal and even escapes stay eligible" {
  let odd_escape = resolve_delimiter_events([
    delimiter_test_run(
      AsteriskDelimiter,
      0,
      1,
      DelimiterWhitespace,
      DelimiterOther,
      escaped=true,
    ),
    delimiter_test_fact(AsteriskDelimiter, 4, 1, false, true),
  ])
  assert_eq(odd_escape.events.iter().to_array(), [
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(0, 1)),
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(4, 5)),
  ])
  // The fact adapter reports an even backslash run as unescaped.
  let even_escape = resolve_delimiter_events([
    delimiter_test_run(
      AsteriskDelimiter,
      1,
      1,
      DelimiterWhitespace,
      DelimiterOther,
      escaped=false,
    ),
    delimiter_test_fact(AsteriskDelimiter, 5, 1, false, true),
  ])
  assert_eq(even_escape.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(1, 2)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(5, 6)),
  ])
}

///|
test "delimiter resolver: escaped markers split from adjacent eligible runs" {
  // CommonMark 437: `foo *\**`. The backslash at [5, 6) is ordinary parser
  // input; only the escaped marker at [6, 7) enters this delimiter plan.
  let emphasis = resolve_delimiter_events([
    delimiter_test_run(
      AsteriskDelimiter,
      4,
      1,
      DelimiterWhitespace,
      DelimiterPunctuationOrSymbol,
    ),
    delimiter_test_run(
      AsteriskDelimiter,
      6,
      1,
      DelimiterPunctuationOrSymbol,
      DelimiterPunctuationOrSymbol,
      escaped=true,
    ),
    delimiter_test_run(
      AsteriskDelimiter,
      7,
      1,
      DelimiterPunctuationOrSymbol,
      DelimiterWhitespace,
    ),
  ])
  assert_eq(emphasis.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(4, 5)),
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(6, 7)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(7, 8)),
  ])
  // CommonMark 440: `foo **\***`. The same split preserves a strong closer.
  let strong = resolve_delimiter_events([
    delimiter_test_run(
      AsteriskDelimiter,
      4,
      2,
      DelimiterWhitespace,
      DelimiterPunctuationOrSymbol,
    ),
    delimiter_test_run(
      AsteriskDelimiter,
      7,
      1,
      DelimiterPunctuationOrSymbol,
      DelimiterPunctuationOrSymbol,
      escaped=true,
    ),
    delimiter_test_run(
      AsteriskDelimiter,
      8,
      2,
      DelimiterPunctuationOrSymbol,
      DelimiterWhitespace,
    ),
  ])
  assert_eq(strong.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(4, 6)),
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(7, 8)),
    CloseEmphasisDelimiter(ResolvedStrong, DelimiterSourceRange(8, 10)),
  ])
}

///|
test "delimiter resolver: link labels use a stack bottom without resetting outer runs" {
  let plan = resolve_delimiter_events([
    delimiter_test_run(
      AsteriskDelimiter,
      0,
      1,
      DelimiterWhitespace,
      DelimiterOther,
    ),
    PushLinkLabelScope,
    delimiter_test_run(
      AsteriskDelimiter,
      6,
      1,
      DelimiterWhitespace,
      DelimiterOther,
    ),
    delimiter_test_run(
      AsteriskDelimiter,
      10,
      1,
      DelimiterOther,
      DelimiterWhitespace,
    ),
    ResolveLinkLabelScope,
    delimiter_test_run(
      AsteriskDelimiter,
      18,
      1,
      DelimiterOther,
      DelimiterWhitespace,
    ),
  ])
  assert_eq(plan.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(0, 1)),
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(6, 7)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(10, 11)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(18, 19)),
  ])
}

///|
test "delimiter resolver: link label scope blocks delimiter escape both ways" {
  let closer_cannot_escape = resolve_delimiter_events([
    delimiter_test_fact(AsteriskDelimiter, 0, 1, true, false),
    PushLinkLabelScope,
    delimiter_test_fact(AsteriskDelimiter, 6, 1, false, true),
    ResolveLinkLabelScope,
  ])
  assert_eq(closer_cannot_escape.events.iter().to_array(), [
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(0, 1)),
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(6, 7)),
  ])
  let opener_cannot_escape = resolve_delimiter_events([
    PushLinkLabelScope,
    delimiter_test_fact(AsteriskDelimiter, 1, 1, true, false),
    ResolveLinkLabelScope,
    delimiter_test_fact(AsteriskDelimiter, 6, 1, false, true),
  ])
  assert_eq(opener_cannot_escape.events.iter().to_array(), [
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(1, 2)),
    LiteralEmphasisDelimiter(AsteriskDelimiter, DelimiterSourceRange(6, 7)),
  ])
}

///|
test "delimiter resolver: omitted code-span facts leave outer state intact" {
  // The parser shell emits one opaque event, not a run fact for the '*'
  // inside its range.
  let plan = resolve_delimiter_events([
    delimiter_test_fact(AsteriskDelimiter, 0, 1, true, false),
    OpaqueInlineEvent(DelimiterSourceRange(3, 6)),
    delimiter_test_fact(AsteriskDelimiter, 7, 1, false, true),
  ])
  assert_eq(plan.events.iter().to_array(), [
    OpenEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(0, 1)),
    CloseEmphasisDelimiter(ResolvedEmphasis, DelimiterSourceRange(7, 8)),
  ])
}

///|
fn delimiter_failed_opener_search_events(
  run_count : Int,
) -> Array[DelimiterResolverEvent] {
  let events : Array[DelimiterResolverEvent] = []
  for i = 0; i < run_count; i = i + 1 {
    events.push(
      delimiter_test_run(
        UnderscoreDelimiter,
        i * 2,
        1,
        DelimiterWhitespace,
        DelimiterOther,
      ),
    )
  }
  for i = 0; i < run_count; i = i + 1 {
    events.push(
      delimiter_test_run(
        AsteriskDelimiter,
        (run_count + i) * 2,
        1,
        DelimiterOther,
        DelimiterWhitespace,
      ),
    )
  }
  events
}

///|
test "delimiter resolver: failed opener searches stay linear" {
  let run_count = 256
  let events = delimiter_failed_opener_search_events(run_count)
  let plan = resolve_delimiter_events(events)
  assert_eq(plan.events.length(), run_count * 2)
  assert_true(
    plan.events
    .iter()
    .all(fn(event) {
      match event {
        LiteralEmphasisDelimiter(_, _) => true
        _ => false
      }
    }),
  )
  assert_eq(plan.stats.run_count, run_count * 2)
  inspect(plan.stats.opener_checks, content="256")
}

///|
fn benchmark_delimiter_failed_opener_search(
  b : @bench.T,
  run_count : Int,
) -> Unit {
  let events = delimiter_failed_opener_search_events(run_count)
  b.bench(fn() { b.keep(resolve_delimiter_events(events)) })
}

///|
test "bench: delimiter resolver failed opener search R=512" (b : @bench.T) {
  benchmark_delimiter_failed_opener_search(b, 512)
}

///|
test "bench: delimiter resolver failed opener search R=1024" (b : @bench.T) {
  benchmark_delimiter_failed_opener_search(b, 1024)
}

///|
test "bench: delimiter resolver failed opener search R=2048" (b : @bench.T) {
  benchmark_delimiter_failed_opener_search(b, 2048)
}

///|
test "panic delimiter resolver: rejects empty runs" {
  ignore(
    resolve_delimiter_events([
      delimiter_test_run(
        AsteriskDelimiter,
        0,
        0,
        DelimiterWhitespace,
        DelimiterOther,
      ),
    ]),
  )
}
