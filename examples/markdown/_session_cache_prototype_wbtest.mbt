// PROTOTYPE — #908 integrated session-owned Markdown lexer probe.
//
// This file is intentionally throwaway. It exercises the session through the
// actual lexer step path before production API and documentation decisions.

///|
fn prototype_session_tokenize(source : String) -> Array[@core.TokenInfo[Token]] {
  let session = MarkdownLexSession()
  let tokens : Array[@core.TokenInfo[Token]] = []
  let mut pos = 0
  let mut mode = LineStart
  while pos < source.length() {
    let (step, next_mode) = session.step(source, pos, mode)
    match step {
      Produced(info, next_offset~) => {
        guard next_offset > pos else { break }
        tokens.push(info)
        pos = next_offset
        mode = next_mode
      }
      Invalid(at~, width~, ..) => {
        pos = at + width
        mode = next_mode
      }
      Incomplete(..) => break
      Done => break
    }
  }
  tokens.push(@core.TokenInfo::new(EOF, 0))
  tokens
}

///|
fn prototype_baseline_tokenize(
  source : String,
) -> Array[@core.TokenInfo[Token]] raise @core.LexError {
  clear_detached_code_block_step()
  clear_same_line_list_item_prefix_cache()
  @core.tokenize_with_modes(markdown_mode_lexer, source, EOF).0
}

///|
fn prototype_source(line_count : Int, indent : String) -> String {
  let out = StringBuilder::new()
  out.write_string("- item\n")
  out.write_string(indent + "```\n")
  for i = 0; i < line_count; i = i + 1 {
    out.write_string(indent + "code_" + i.to_string() + "\n")
  }
  out.write_string(indent + "```\n")
  out.to_string()
}

///|
fn prototype_line_starts(source : String) -> Array[Int] {
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
test "integrated session tokenization matches baseline" {
  for
    source in [
      "# heading\nparagraph\n",
      "- one\n  - two\n  text\n",
      "> quote\n> continuation\n",
      prototype_source(32, "  "),
      "- outer\n  > quote\n  ```\n  code\n  ```\n",
    ] {
    assert_eq(
      prototype_session_tokenize(source),
      prototype_baseline_tokenize(source),
    )
  }
}

///|
fn assert_prototype_lex_step_equal(
  actual : @core.LexStep[Token],
  expected : @core.LexStep[Token],
  source : String,
) -> Unit raise {
  assert_eq(
    next_lex_step_offset(actual, source),
    next_lex_step_offset(expected, source),
  )
  match (actual, expected) {
    (Produced(actual_info, ..), Produced(expected_info, ..)) =>
      assert_eq(actual_info, expected_info)
    (Done, Done) => ()
    _ => ()
  }
}

///|
test "integrated sessions remain independent when interleaved" {
  let first = prototype_source(32, "  ")
  let second = prototype_source(32, "    ")
  let first_session = MarkdownLexSession()
  let second_session = MarkdownLexSession()
  let first_positions = prototype_line_starts(first)
  let second_positions = prototype_line_starts(second)
  for i = 1; i < first_positions.length() - 1; i = i + 1 {
    let first_pos = first_positions[i]
    let second_pos = second_positions[i]
    let (first_step, _) = first_session.step(
      first,
      first_pos,
      CodeBlock(3, '`'),
    )
    let (second_step, _) = second_session.step(
      second,
      second_pos,
      CodeBlock(3, '`'),
    )
    clear_detached_code_block_step()
    let (first_expected, _) = markdown_lex_step(
      first,
      first_pos,
      CodeBlock(3, '`'),
    )
    clear_detached_code_block_step()
    let (second_expected, _) = markdown_lex_step(
      second,
      second_pos,
      CodeBlock(3, '`'),
    )
    assert_prototype_lex_step_equal(first_step, first_expected, first)
    assert_prototype_lex_step_equal(second_step, second_expected, second)
  }
}

///|
test "integrated session source replacement and reset" {
  let first = prototype_source(16, "  ")
  let second = prototype_source(16, "    ")
  let session = MarkdownLexSession()
  let first_pos = prototype_line_starts(first)[8]
  let second_pos = prototype_line_starts(second)[8]
  let (first_step, _) = session.step(first, first_pos, CodeBlock(3, '`'))
  let (second_step, _) = session.step(second, second_pos, CodeBlock(3, '`'))
  clear_detached_code_block_step()
  let (first_expected, _) = markdown_lex_step(
    first,
    first_pos,
    CodeBlock(3, '`'),
  )
  clear_detached_code_block_step()
  let (second_expected, _) = markdown_lex_step(
    second,
    second_pos,
    CodeBlock(3, '`'),
  )
  assert_prototype_lex_step_equal(first_step, first_expected, first)
  assert_prototype_lex_step_equal(second_step, second_expected, second)
  session.reset()
  let (reset_step, _) = session.step(first, first_pos, CodeBlock(3, '`'))
  assert_prototype_lex_step_equal(reset_step, first_expected, first)
}

///|
fn prototype_session_replay_workload(
  source : String,
  positions : Array[Int],
) -> Int {
  let session = MarkdownLexSession()
  let mut checksum = 0
  for i = 1; i < positions.length() - 1; i = i + 1 {
    let (step, _) = session.step(source, positions[i], CodeBlock(3, '`'))
    checksum += next_lex_step_offset(step, source)
  }
  checksum
}

///|
fn prototype_stateless_replay_workload(
  source : String,
  positions : Array[Int],
) -> Int {
  let mut checksum = 0
  for i = 1; i < positions.length() - 1; i = i + 1 {
    clear_detached_code_block_step()
    let (step, _) = markdown_lex_step(source, positions[i], CodeBlock(3, '`'))
    checksum += next_lex_step_offset(step, source)
  }
  checksum
}

///|
test "integrated session replay: 1024 lines" (b : @bench.T) {
  let source = prototype_source(1024, "  ")
  let positions = prototype_line_starts(source)
  b.bench(() => b.keep(prototype_session_replay_workload(source, positions)))
}

///|
test "integrated stateless replay control: 1024 lines" (b : @bench.T) {
  let source = prototype_source(1024, "  ")
  let positions = prototype_line_starts(source)
  b.bench(() => b.keep(prototype_stateless_replay_workload(source, positions)))
}
