// Detached fence replay benchmarks.
//
// These isolate the source-derived fallback from the normal stateful lexer.
// The fallback is only needed by the public, detached stepping API.

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
test "detached code replay cache clears at source end" {
  let source = "```\ncode"
  let (_, _) = markdown_lex_step(source, "```\n".length(), CodeBlock(3, '`'))
  assert_true(detached_code_block_indent_cache.val is None)
}

///|
test "detached code replay cache skips oversized source" {
  let source = "```\ncode\n" +
    "x".repeat(DETACHED_CODE_BLOCK_CACHE_MAX_SOURCE_LENGTH + 1)
  clear_detached_code_block_step()
  let (_, _) = markdown_lex_step(source, "```\n".length(), CodeBlock(3, '`'))
  assert_true(detached_code_block_indent_cache.val is None)
}

///|
test "detached code replay cache replaces source" {
  let first_builder = StringBuilder::StringBuilder()
  first_builder.write_string("```\nfirst\nnext\n")
  let first_source = first_builder.to_string()
  let second_builder = StringBuilder::StringBuilder()
  second_builder.write_string("```\nsecond\nnext\n")
  let second_source = second_builder.to_string()
  clear_detached_code_block_step()
  let _ = detached_code_block_indent_for_step(first_source, 4, 3, '`')
  let _ = detached_code_block_indent_for_step(second_source, 4, 3, '`')
  match detached_code_block_indent_cache.val {
    Some(cache) => assert_true(physical_equal(cache.source, second_source))
    None => fail("detached code replay cache was not populated")
  }
  clear_detached_code_block_step()
}

///|
test "detached code replay cache restarts on backward stepping" {
  let source = "```\nfirst\nsecond\n"
  clear_detached_code_block_step()
  let _ = detached_code_block_indent_for_step(source, 10, 3, '`')
  let _ = detached_code_block_indent_for_step(source, 4, 3, '`')
  match detached_code_block_indent_cache.val {
    Some(cache) => assert_eq(cache.next_pos, 4)
    None => fail("detached code replay cache was not populated")
  }
  clear_detached_code_block_step()
}

///|
test "detached code replay cache clears after closing fence" {
  let source = "```\ncode\n```\nnext\n"
  clear_detached_code_block_step()
  let (_, _) = markdown_lex_step(source, 4, CodeBlock(3, '`'))
  let (_, _) = markdown_lex_step(
    source,
    "```\ncode\n".length(),
    CodeBlock(3, '`'),
  )
  assert_true(detached_code_block_indent_cache.val is None)
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
  clear_detached_code_block_step()
  let mut checksum = 0
  for i = 1; i < line_starts.length() - 1; i = i + 1 {
    let (step, _) = markdown_lex_step(source, line_starts[i], CodeBlock(3, '`'))
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
    clear_detached_code_block_step()
    let (step, _) = markdown_lex_step(source, line_starts[i], CodeBlock(3, '`'))
    checksum += next_lex_step_offset(step, source)
  }
  checksum
}

///|
test "detached fence replay from middle: 1024 lines uncached control" (
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
