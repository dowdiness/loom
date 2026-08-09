// Source-derived fence ownership benchmarks.
//
// These exercise the detached replay fallback's list-ownership walk directly.
// The stateful lexer carries the opening indent and does not use this path.

///|
fn source_list_owned_benchmark_input(depth : Int) -> (String, Int, Int) {
  let buf = StringBuilder::StringBuilder()
  let mut source_length = 0
  for level = 0; level < depth; level = level + 1 {
    let line = " ".repeat(level * 2) + "- item\n"
    buf.write_string(line)
    source_length += line.length()
  }
  let fence_start = source_length
  let fence_indent = depth * 2
  buf.write_string(" ".repeat(fence_indent) + "```\n")
  (buf.to_string(), fence_start, fence_indent)
}

///|
test "deep list-owned fence ownership remains available" {
  let (source, fence_start, fence_indent) = source_list_owned_benchmark_input(
    256,
  )
  assert_true(source_line_is_list_owned(source, fence_start, fence_indent))
}

///|
test "source list ownership rejects over-indented fence" {
  let source = "- item\n      ```\n"
  let fence_start = "- item\n".length()
  assert_false(source_line_is_list_owned(source, fence_start, 6))
}

///|
fn source_list_owned_workload(
  source : String,
  fence_start : Int,
  fence_indent : Int,
) -> Int {
  if source_line_is_list_owned(source, fence_start, fence_indent) {
    1
  } else {
    0
  }
}

///|
test "source list ownership walk: 16 nested levels" (b : @bench.T) {
  let (source, fence_start, fence_indent) = source_list_owned_benchmark_input(
    16,
  )
  b.bench(() => {
    b.keep(source_list_owned_workload(source, fence_start, fence_indent))
  })
}

///|
test "source list ownership walk: 64 nested levels" (b : @bench.T) {
  let (source, fence_start, fence_indent) = source_list_owned_benchmark_input(
    64,
  )
  b.bench(() => {
    b.keep(source_list_owned_workload(source, fence_start, fence_indent))
  })
}

///|
test "source list ownership walk: 256 nested levels" (b : @bench.T) {
  let (source, fence_start, fence_indent) = source_list_owned_benchmark_input(
    256,
  )
  b.bench(() => {
    b.keep(source_list_owned_workload(source, fence_start, fence_indent))
  })
}
