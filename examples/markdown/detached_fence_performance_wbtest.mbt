// Detached fence replay benchmarks.
//
// The stateless public step is the correctness baseline. Reusable replay is
// owned by MarkdownLexSession and is measured separately.

///|
fn detached_fence_benchmark_source(line_count : Int) -> String {
  let buf = StringBuilder::StringBuilder()
  buf.write_string("- item\n  ```\n")
  for i = 0; i < line_count; i = i + 1 {
    buf.write_string("  code_" + i.to_string() + "\n")
  }
  buf.write_string("  ```\n")
  buf.to_string()
}

///|
fn detached_fence_line_starts(source : String) -> Array[Int] {
  let starts : Array[Int] = [0]
  let mut cursor = 0
  while cursor < source.length() {
    let line_end = find_line_end(source, cursor)
    let next = line_end_including_break(source, line_end)
    if next < source.length() {
      starts.push(next)
    }
    if next <= cursor {
      break
    }
    cursor = next
  }
  starts
}

///|
test "detached fence replay state matches stateless scan" {
  let source = detached_fence_benchmark_source(32)
  let line_starts = detached_fence_line_starts(source)
  let mut state = source_fence_replay_initial(source, 3, '`')
  for pos in line_starts {
    let (next_state, replay_indent) = source_fence_replay_until(state, pos)
    assert_eq(
      replay_indent,
      source_derived_code_block_indent(source, pos, 3, '`'),
    )
    state = next_state
  }
}

///|
test "session replay clears at source end" {
  let source = "```\ncode"
  let session = MarkdownLexSession()
  let (_, _) = session.step(source, "```\n".length(), CodeBlock(3, '`'))
  assert_true(session.detached_cache.val is None)
}

///|
test "session replay skips oversized source" {
  let source = "```\ncode\n" +
    "x".repeat(DETACHED_CODE_BLOCK_CACHE_MAX_SOURCE_LENGTH + 1)
  let session = MarkdownLexSession()
  let (_, _) = session.step(source, "```\n".length(), CodeBlock(3, '`'))
  assert_true(session.detached_cache.val is None)
}

///|
test "session replay replaces source" {
  let first_source = "```\nfirst\nnext\n"
  let second_source = "```\nsecond\nnext\n"
  let session = MarkdownLexSession()
  let _ = session.step(first_source, 4, CodeBlock(3, '`'))
  let _ = session.step(second_source, 4, CodeBlock(3, '`'))
  match session.detached_cache.val {
    Some(cache) => assert_true(physical_equal(cache.source, second_source))
    None => fail("session replay cache was not populated")
  }
}

///|
test "session replay remains correct on backward stepping" {
  let source = "```\nfirst\nsecond\n"
  let session = MarkdownLexSession()
  let _ = session.step(source, 10, CodeBlock(3, '`'))
  let (actual, actual_mode) = session.step(source, 4, CodeBlock(3, '`'))
  let (expected, expected_mode) = markdown_lex_step(
    source,
    4,
    CodeBlock(3, '`'),
  )
  assert_eq(actual_mode, expected_mode)
  assert_prototype_lex_step_equal(actual, expected, source)
}

///|
test "session replay clears after closing fence" {
  let source = "```\ncode\n```\nnext\n"
  let session = MarkdownLexSession()
  let (_, _) = session.step(source, 4, CodeBlock(3, '`'))
  let (_, _) = session.step(source, "```\ncode\n".length(), CodeBlock(3, '`'))
  assert_true(session.detached_cache.val is None)
}

///|
fn detached_fence_scan_workload(
  source : String,
  line_starts : Array[Int],
) -> Int {
  let mut checksum = 0
  for pos in line_starts {
    checksum += source_derived_code_block_indent(source, pos, 3, '`').unwrap_or(
      -1,
    )
  }
  checksum
}

///|
test "detached fence source scan: 256 lines" (b : @bench.T) {
  let source = detached_fence_benchmark_source(256)
  let line_starts = detached_fence_line_starts(source)
  b.bench(() => b.keep(detached_fence_scan_workload(source, line_starts)))
}

///|
test "detached fence source scan: 1024 lines" (b : @bench.T) {
  let source = detached_fence_benchmark_source(1024)
  let line_starts = detached_fence_line_starts(source)
  b.bench(() => b.keep(detached_fence_scan_workload(source, line_starts)))
}

///|
fn detached_fence_replay_workload(
  source : String,
  line_starts : Array[Int],
) -> Int {
  let mut mode = LineStart
  let mut checksum = 0
  for pos in line_starts {
    let (step, next_mode) = markdown_lex_step(source, pos, mode)
    checksum += next_lex_step_offset(step, source)
    mode = next_mode
  }
  checksum
}

///|
fn detached_middle_replay_workload(
  source : String,
  line_starts : Array[Int],
) -> Int {
  let session = MarkdownLexSession()
  let mut checksum = 0
  for i = 1; i < line_starts.length() - 1; i = i + 1 {
    let (step, _) = session.step(source, line_starts[i], CodeBlock(3, '`'))
    checksum += next_lex_step_offset(step, source)
  }
  checksum
}

///|
test "detached fence replay from middle: 1024 lines" (b : @bench.T) {
  let source = detached_fence_benchmark_source(1024)
  let line_starts = detached_fence_line_starts(source)
  b.bench(() => b.keep(detached_middle_replay_workload(source, line_starts)))
}

///|
fn detached_middle_replay_uncached_workload(
  source : String,
  line_starts : Array[Int],
) -> Int {
  let mut checksum = 0
  for i = 1; i < line_starts.length() - 1; i = i + 1 {
    let (step, _) = markdown_lex_step(source, line_starts[i], CodeBlock(3, '`'))
    checksum += next_lex_step_offset(step, source)
  }
  checksum
}

///|
test "detached fence replay from middle: 1024 lines stateless control" (
  b : @bench.T,
) {
  let source = detached_fence_benchmark_source(1024)
  let line_starts = detached_fence_line_starts(source)
  b.bench(() => {
    b.keep(detached_middle_replay_uncached_workload(source, line_starts))
  })
}

///|
test "detached fence replay: 256 lines" (b : @bench.T) {
  let source = detached_fence_benchmark_source(256)
  let line_starts = detached_fence_line_starts(source)
  b.bench(() => b.keep(detached_fence_replay_workload(source, line_starts)))
}

///|
test "detached fence replay: 1024 lines" (b : @bench.T) {
  let source = detached_fence_benchmark_source(1024)
  let line_starts = detached_fence_line_starts(source)
  b.bench(() => b.keep(detached_fence_replay_workload(source, line_starts)))
}
