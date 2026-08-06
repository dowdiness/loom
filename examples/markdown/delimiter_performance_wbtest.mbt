// End-to-end Markdown delimiter benchmarks.
//
// Each `Nx` fixture repeats the same seven semantic motifs. The plain control
// preserves every UTF-16 code-unit position while replacing Markdown syntax.
// Incremental rows report one delimiter edit plus its same-length restore.

///|
priv struct DelimiterPerformanceFixture {
  source : String
  edited : String
  edit : @core.Edit
} derive(Eq)

///|
priv struct DelimiterPerformanceWorkloads {
  delimiter_heavy : DelimiterPerformanceFixture
  plain_control : DelimiterPerformanceFixture
} derive(Eq)

///|
fn delimiter_performance_motifs() -> Array[String] {
  [
    // Alternating `*` / `_` runs cannot cross-match.
    "*a _b* c_",
    // Adjacent runs exercise an interior strong pair.
     "*foo**bar**baz*",
    // Unequal triple/double runs leave partial literal markers.
     "***part** **tail***",
    // Nested strong and emphasis runs.
     "**outer *inner* tail**",
    // A dual-purpose triple run exercises the rule of three.
     "*a***a*",
    // Link-label scope keeps inner and outer delimiters separate.
     "*outer [*inner*](/url) tail*",
    // Delimiters inside the code span are opaque to emphasis resolution.
     "*outer `*opaque*` tail*",
  ]
}

///|
fn delimiter_performance_plain_control(source : String) -> String {
  let builder = StringBuilder::StringBuilder()
  for character in source {
    match character {
      '*' | '_' | '`' | '[' | ']' | '(' | ')' | '/' => builder.write_char('x')
      _ => builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
// The control keeps the conflict workload's byte length and delimiter counts,
// but moves one right bracket out of each code span. It is deliberately named
// as a token-count control rather than an equivalent Markdown-shape control:
// the extra closing brackets are part of the measured recovery workload.
fn delimiter_performance_code_conflict_workloads(
  repeat_count : Int,
) -> (String, String) {
  guard repeat_count > 0 else {
    abort("delimiter performance conflict repeat count must be positive")
  }
  let conflict = "[a `x]` b] [c `y]` d] ![e `z]` f]\n".repeat(repeat_count)
  let token_count_control = "[a `x` b]] [c `y` d]] ![e `z` f]]\n".repeat(
    repeat_count,
  )
  guard conflict.length() == token_count_control.length() else {
    abort("delimiter performance conflict control length mismatch")
  }
  (conflict, token_count_control)
}

///|
fn delimiter_performance_replace_one(
  source : String,
  start : Int,
  replacement : String,
) -> String {
  source[:start].to_owned() + replacement + source[start + 1:].to_owned()
}

///|
fn delimiter_performance_workloads(
  repeat_count : Int,
) -> DelimiterPerformanceWorkloads {
  guard repeat_count > 0 else {
    abort("delimiter performance repeat count must be positive")
  }
  let motifs = delimiter_performance_motifs()
  let builder = StringBuilder::StringBuilder()
  let mut source_offset = 0
  let mut edit_start = -1
  for repetition in 0..<repeat_count {
    for motif_index, motif in motifs {
      if source_offset > 0 {
        builder.write_char(' ')
        source_offset += 1
      }
      if repetition == repeat_count / 2 && motif_index == 4 {
        edit_start = source_offset
      }
      builder.write_string(motif)
      source_offset += motif.length()
    }
  }
  builder.write_char('\n')
  let delimiter_source = builder.to_string()
  let plain_source = delimiter_performance_plain_control(delimiter_source)
  guard edit_start >= 0 else {
    abort("delimiter performance edit site was not generated")
  }
  let edit = @core.Edit::new(edit_start, 1, 1)
  {
    delimiter_heavy: {
      source: delimiter_source,
      edited: delimiter_performance_replace_one(
        delimiter_source, edit_start, "_",
      ),
      edit,
    },
    plain_control: {
      source: plain_source,
      edited: delimiter_performance_replace_one(plain_source, edit_start, "y"),
      edit,
    },
  }
}

///|
fn delimiter_performance_push_run(
  events : Array[DelimiterResolverEvent],
  start : Int,
  marker : EmphasisDelimiterMarker,
  length : Int,
  can_open : Bool,
  can_close : Bool,
) -> Int {
  events.push(DelimiterRunEvent({ marker, start, length, can_open, can_close }))
  start + length + 1
}

///|
fn delimiter_performance_push_runs(
  events : Array[DelimiterResolverEvent],
  start : Int,
  runs : Array[(EmphasisDelimiterMarker, Int, Bool, Bool)],
) -> Int {
  let mut position = start
  for run in runs {
    let (marker, length, can_open, can_close) = run
    position = delimiter_performance_push_run(
      events, position, marker, length, can_open, can_close,
    )
  }
  position
}

///|
fn delimiter_performance_resolver_event_bank(
  repeat_count : Int,
) -> Array[DelimiterResolverEvent] {
  guard repeat_count > 0 else {
    abort("delimiter resolver event-bank repeat count must be positive")
  }
  let events : Array[DelimiterResolverEvent] = []
  let mut position = 0
  for _ in 0..<repeat_count {
    // 1. Alternating marker kinds.
    position = delimiter_performance_push_runs(events, position, [
      (AsteriskDelimiter, 1, true, false),
      (UnderscoreDelimiter, 1, true, false),
      (AsteriskDelimiter, 1, false, true),
      (UnderscoreDelimiter, 1, false, true),
    ])

    // 2. Adjacent dual-purpose runs between an outer pair.
    position = delimiter_performance_push_runs(events, position, [
      (AsteriskDelimiter, 1, true, false),
      (AsteriskDelimiter, 2, true, true),
      (AsteriskDelimiter, 2, true, true),
      (AsteriskDelimiter, 1, false, true),
    ])

    // 3. Partial triple/double matches consume their residual markers.
    position = delimiter_performance_push_runs(events, position, [
      (AsteriskDelimiter, 3, true, false),
      (AsteriskDelimiter, 2, false, true),
      (AsteriskDelimiter, 2, true, false),
      (AsteriskDelimiter, 3, false, true),
    ])

    // 4. Nested strong and emphasis pairs.
    position = delimiter_performance_push_runs(events, position, [
      (AsteriskDelimiter, 2, true, false),
      (AsteriskDelimiter, 1, true, false),
      (AsteriskDelimiter, 1, false, true),
      (AsteriskDelimiter, 2, false, true),
    ])

    // 5. Divisible dual-purpose triples exercise the rule of three.
    position = delimiter_performance_push_runs(events, position, [
      (AsteriskDelimiter, 3, true, true),
      (AsteriskDelimiter, 3, true, true),
    ])

    // 6. Link-label scope resolves an inner pair before the outer closer.
    position = delimiter_performance_push_run(
      events,
      position,
      AsteriskDelimiter,
      1,
      true,
      false,
    )
    events.push(PushLinkLabelScope)
    position = delimiter_performance_push_runs(events, position, [
      (AsteriskDelimiter, 1, true, false),
      (AsteriskDelimiter, 1, false, true),
    ])
    events.push(ResolveLinkLabelScope)
    position = delimiter_performance_push_run(
      events,
      position,
      AsteriskDelimiter,
      1,
      false,
      true,
    )

    // 7. One opaque code-span range separates an outer pair.
    position = delimiter_performance_push_run(
      events,
      position,
      AsteriskDelimiter,
      1,
      true,
      false,
    )
    let opaque_end = position + 3
    events.push(OpaqueInlineEvent(DelimiterSourceRange(position, opaque_end)))
    position = opaque_end + 1
    position = delimiter_performance_push_run(
      events,
      position,
      AsteriskDelimiter,
      1,
      false,
      true,
    )
  }
  events
}

///|
fn assert_delimiter_performance_parser_matches_fresh(
  source_identity : String,
  label : String,
  parser : @loom.SyntaxParser,
  source : String,
) -> Unit raise {
  let fresh = delimiter_performance_new_syntax_parser(source_identity, source)
  guard parser.source().read_or_abort() == source else {
    fail("unexpected incremental source: " + label)
  }
  guard parser.syntax_tree().read_or_abort() ==
    fresh.syntax_tree().read_or_abort() else {
    fail("incremental syntax differs from a fresh parse: " + label)
  }
  guard parser.diagnostics().read_or_abort().format() ==
    fresh.diagnostics().read_or_abort().format() else {
    fail("incremental diagnostics differ from a fresh parse: " + label)
  }
}

///|
fn assert_delimiter_performance_incremental_parity(
  source_identity : String,
  label : String,
  fixture : DelimiterPerformanceFixture,
) -> Unit raise {
  let parser = delimiter_performance_new_syntax_parser(
    source_identity,
    fixture.source,
  )
  try! parser.apply_edit(fixture.edit, fixture.edited)
  assert_delimiter_performance_parser_matches_fresh(
    source_identity,
    label + " after edit",
    parser,
    fixture.edited,
  )
  try! parser.apply_edit(fixture.edit, fixture.source)
  assert_delimiter_performance_parser_matches_fresh(
    source_identity,
    label + " after restore",
    parser,
    fixture.source,
  )
}

///|
test "delimiter performance workload is deterministic and length matched" {
  assert_eq(delimiter_performance_motifs().length(), 7)
  for repeat_count in [64, 256] {
    let first = delimiter_performance_workloads(repeat_count)
    let second = delimiter_performance_workloads(repeat_count)
    guard first == second else {
      fail("expected deterministic delimiter performance workloads")
    }
    assert_eq(
      first.delimiter_heavy.source.length(),
      first.plain_control.source.length(),
    )
    assert_eq(
      first.delimiter_heavy.edited.length(),
      first.plain_control.edited.length(),
    )
    assert_eq(
      first.delimiter_heavy.source.length(),
      first.delimiter_heavy.edited.length(),
    )
    assert_eq(first.delimiter_heavy.edit.old_len, 1)
    assert_eq(first.delimiter_heavy.edit.new_len, 1)
    assert_eq(first.delimiter_heavy.edit.start, first.plain_control.edit.start)
    let edit_start = first.delimiter_heavy.edit.start
    assert_eq(
      first.delimiter_heavy.source[edit_start:edit_start + 1].to_owned(),
      "*",
    )
    assert_eq(
      first.delimiter_heavy.edited[edit_start:edit_start + 1].to_owned(),
      "_",
    )
    assert_eq(
      first.plain_control.source[edit_start:edit_start + 1].to_owned(),
      "x",
    )
    assert_eq(
      first.plain_control.edited[edit_start:edit_start + 1].to_owned(),
      "y",
    )
  }
}

///|
test "delimiter performance conflict workload scales with matched control" {
  let (small_conflict, small_control) = delimiter_performance_code_conflict_workloads(
    64,
  )
  let (large_conflict, large_control) = delimiter_performance_code_conflict_workloads(
    256,
  )
  assert_eq(small_conflict.length(), small_control.length())
  assert_eq(large_conflict.length(), large_control.length())
  assert_eq(large_conflict.length(), small_conflict.length() * 4)
  assert_eq(large_control.length(), small_control.length() * 4)
}

///|
fn benchmark_delimiter_performance_code_conflict(
  b : @bench.T,
  source_identity : String,
  source : String,
) -> Unit {
  benchmark_delimiter_performance_full_parse(b, source_identity, source)
}

///|
test "markdown code-conflict 64x full parse" (b : @bench.T) {
  let (conflict, _) = delimiter_performance_code_conflict_workloads(64)
  benchmark_delimiter_performance_code_conflict(
    b, "markdown-code-conflict-64-full", conflict,
  )
}

///|
test "markdown code-conflict token-count control 64x full parse" (b : @bench.T) {
  let (_, control) = delimiter_performance_code_conflict_workloads(64)
  benchmark_delimiter_performance_code_conflict(
    b, "markdown-code-conflict-token-count-control-64-full", control,
  )
}

///|
test "markdown code-conflict 256x full parse" (b : @bench.T) {
  let (conflict, _) = delimiter_performance_code_conflict_workloads(256)
  benchmark_delimiter_performance_code_conflict(
    b, "markdown-code-conflict-256-full", conflict,
  )
}

///|
test "markdown code-conflict token-count control 256x full parse" (b : @bench.T) {
  let (_, control) = delimiter_performance_code_conflict_workloads(256)
  benchmark_delimiter_performance_code_conflict(
    b, "markdown-code-conflict-token-count-control-256-full", control,
  )
}

///|
test "delimiter performance incremental edit and restore match fresh parses" {
  let source_identity = "markdown-delimiter-performance-parity"
  for repeat_count in [64, 256] {
    let workloads = delimiter_performance_workloads(repeat_count)
    assert_delimiter_performance_incremental_parity(
      source_identity,
      "delimiter-heavy \{repeat_count}x",
      workloads.delimiter_heavy,
    )
    assert_delimiter_performance_incremental_parity(
      source_identity,
      "plain-control \{repeat_count}x",
      workloads.plain_control,
    )
  }
}

///|
test "delimiter performance resolver operation counts stay linear" {
  let checks : Array[Int] = []
  for repeat_count in [64, 256] {
    let events = delimiter_performance_resolver_event_bank(repeat_count)
    let plan = resolve_delimiter_events(events)
    assert_eq(plan.stats.run_count, repeat_count * 24)
    assert_eq(plan.stats.opener_checks, repeat_count * 15)
    assert_true(plan.stats.opener_checks <= plan.stats.run_count * 12)
    checks.push(plan.stats.opener_checks)
  }
  assert_eq(checks[1], checks[0] * 4)
}

///|
fn benchmark_delimiter_performance_full_parse(
  b : @bench.T,
  source_identity : String,
  source : String,
) -> Unit {
  let parse = delimiter_performance_full_parse_runner(source_identity, source)
  b.bench(() => b.keep(parse()))
}

///|
fn benchmark_delimiter_performance_incremental_cycle(
  b : @bench.T,
  source_identity : String,
  fixture : DelimiterPerformanceFixture,
) -> Unit {
  let parser = delimiter_performance_new_syntax_parser(
    source_identity,
    fixture.source,
  )
  b.bench(() => {
    try! parser.apply_edit(fixture.edit, fixture.edited)
    b.keep(parser.syntax_tree().read_or_abort())
    try! parser.apply_edit(fixture.edit, fixture.source)
    b.keep(parser.syntax_tree().read_or_abort())
  })
}

///|
test "markdown delimiter-heavy 64x full parse" (b : @bench.T) {
  let workloads = delimiter_performance_workloads(64)
  benchmark_delimiter_performance_full_parse(
    b,
    "markdown-delimiter-heavy-64-full",
    workloads.delimiter_heavy.source,
  )
}

///|
test "markdown plain-control 64x full parse" (b : @bench.T) {
  let workloads = delimiter_performance_workloads(64)
  benchmark_delimiter_performance_full_parse(
    b,
    "markdown-plain-control-64-full",
    workloads.plain_control.source,
  )
}

///|
test "markdown delimiter-heavy 256x full parse" (b : @bench.T) {
  let workloads = delimiter_performance_workloads(256)
  benchmark_delimiter_performance_full_parse(
    b,
    "markdown-delimiter-heavy-256-full",
    workloads.delimiter_heavy.source,
  )
}

///|
test "markdown plain-control 256x full parse" (b : @bench.T) {
  let workloads = delimiter_performance_workloads(256)
  benchmark_delimiter_performance_full_parse(
    b,
    "markdown-plain-control-256-full",
    workloads.plain_control.source,
  )
}

///|
test "markdown delimiter-heavy 64x incremental edit+restore" (b : @bench.T) {
  let workloads = delimiter_performance_workloads(64)
  benchmark_delimiter_performance_incremental_cycle(
    b,
    "markdown-delimiter-heavy-64-incremental",
    workloads.delimiter_heavy,
  )
}

///|
test "markdown plain-control 64x incremental edit+restore" (b : @bench.T) {
  let workloads = delimiter_performance_workloads(64)
  benchmark_delimiter_performance_incremental_cycle(
    b,
    "markdown-plain-control-64-incremental",
    workloads.plain_control,
  )
}

///|
test "markdown delimiter-heavy 256x incremental edit+restore" (b : @bench.T) {
  let workloads = delimiter_performance_workloads(256)
  benchmark_delimiter_performance_incremental_cycle(
    b,
    "markdown-delimiter-heavy-256-incremental",
    workloads.delimiter_heavy,
  )
}

///|
test "markdown plain-control 256x incremental edit+restore" (b : @bench.T) {
  let workloads = delimiter_performance_workloads(256)
  benchmark_delimiter_performance_incremental_cycle(
    b,
    "markdown-plain-control-256-incremental",
    workloads.plain_control,
  )
}
