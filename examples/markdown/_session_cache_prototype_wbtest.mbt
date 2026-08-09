// PROTOTYPE — #908 session-owned Markdown lexer cache API probe.
//
// This file is intentionally throwaway. It probes the state boundary and
// benchmark shape before changing the production lexer or public API.

///|
priv struct SessionCachePrototype {
  detached : Ref[DetachedCodeBlockIndentCache?]
  same_line : Ref[SameLineListItemPrefixFacts?]
}

///|
fn new_session_cache_prototype() -> SessionCachePrototype {
  { detached: { val: None }, same_line: { val: None } }
}

///|
fn prototype_detached_fence_indent(
  session : SessionCachePrototype,
  input : String,
  pos : Int,
  fence_length : Int,
  fence_character : Char,
) -> Int {
  match session.detached.val {
    Some(cache) if cache.next_pos == pos &&
      cache.fence_length == fence_length &&
      cache.fence_character == fence_character &&
      physical_equal(cache.source, input) => cache.opening_indent
    Some(cache) if cache.fence_length == fence_length &&
      cache.fence_character == fence_character &&
      physical_equal(cache.source, input) &&
      pos >= cache.replay.scan_pos => {
      let (replay, opening_indent) = source_fence_replay_until(
        cache.replay,
        pos,
      )
      let indent = opening_indent.unwrap_or(0)
      session.detached.val = Some(DetachedCodeBlockIndentCache::{
        source: cache.source,
        fence_length: cache.fence_length,
        fence_character: cache.fence_character,
        opening_indent: indent,
        next_pos: pos,
        replay,
      })
      indent
    }
    _ => {
      let replay = source_fence_replay_initial(
        input, fence_length, fence_character,
      )
      let (replay, opening_indent) = source_fence_replay_until(replay, pos)
      let indent = opening_indent.unwrap_or(0)
      if input.length() <= DETACHED_CODE_BLOCK_CACHE_MAX_SOURCE_LENGTH {
        session.detached.val = Some(DetachedCodeBlockIndentCache::{
          source: input,
          fence_length,
          fence_character,
          opening_indent: indent,
          next_pos: pos,
          replay,
        })
      } else {
        session.detached.val = None
      }
      indent
    }
  }
}

///|
fn prototype_same_line_facts(
  session : SessionCachePrototype,
  input : String,
  pos : Int,
) -> SameLineListItemPrefixFacts {
  match session.same_line.val {
    Some(facts) if facts.line_start <= pos &&
      pos <= facts.line_end &&
      physical_equal(facts.source, input) => facts
    _ => {
      let line_start = line_start_offset(input, pos)
      let line_end = find_line_end(input, pos)
      let facts = scan_same_line_list_item_prefix(input, line_start, line_end)
      session.same_line.val = Some(facts)
      facts
    }
  }
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
test "prototype session replay matches stateless source replay" {
  let source = prototype_source(64, "  ")
  let session = new_session_cache_prototype()
  for pos in prototype_line_starts(source) {
    let actual = prototype_detached_fence_indent(session, source, pos, 3, '`')
    let expected = source_derived_code_block_indent(source, pos, 3, '`')
    assert_eq(actual, expected.unwrap_or(0))
  }
}

///|
test "prototype sessions remain independent when interleaved" {
  let first = prototype_source(32, "  ")
  let second = prototype_source(32, "    ")
  let first_session = new_session_cache_prototype()
  let second_session = new_session_cache_prototype()
  let first_positions = prototype_line_starts(first)
  let second_positions = prototype_line_starts(second)
  for i = 0; i < first_positions.length(); i = i + 1 {
    let first_pos = first_positions[i]
    let second_pos = second_positions[i]
    let first_actual = prototype_detached_fence_indent(
      first_session, first, first_pos, 3, '`',
    )
    let second_actual = prototype_detached_fence_indent(
      second_session, second, second_pos, 3, '`',
    )
    assert_eq(
      first_actual,
      source_derived_code_block_indent(first, first_pos, 3, '`').unwrap_or(0),
    )
    assert_eq(
      second_actual,
      source_derived_code_block_indent(second, second_pos, 3, '`').unwrap_or(0),
    )
  }
}

///|
test "prototype same-line facts remain independent when interleaved" {
  let first = "- outer\n  - inner\n"
  let second = "> - quote\n> text\n"
  let first_session = new_session_cache_prototype()
  let second_session = new_session_cache_prototype()
  let first_facts = prototype_same_line_facts(first_session, first, 2)
  let second_facts = prototype_same_line_facts(second_session, second, 4)
  assert_eq(first_facts.list_marker_count, 1)
  assert_eq(second_facts.list_marker_count, 1)
  assert_true(first_facts.prefix_end != second_facts.prefix_end)
}

///|
fn prototype_session_replay_workload(
  source : String,
  positions : Array[Int],
) -> Int {
  let session = new_session_cache_prototype()
  let mut checksum = 0
  for pos in positions {
    checksum += prototype_detached_fence_indent(session, source, pos, 3, '`')
  }
  checksum
}

///|
fn prototype_stateless_replay_workload(
  source : String,
  positions : Array[Int],
) -> Int {
  let mut checksum = 0
  for pos in positions {
    checksum += source_derived_code_block_indent(source, pos, 3, '`').unwrap_or(
      0,
    )
  }
  checksum
}

///|
test "prototype session replay: 1024 lines" (b : @bench.T) {
  let source = prototype_source(1024, "  ")
  let positions = prototype_line_starts(source)
  b.bench(() => b.keep(prototype_session_replay_workload(source, positions)))
}

///|
test "prototype stateless replay control: 1024 lines" (b : @bench.T) {
  let source = prototype_source(1024, "  ")
  let positions = prototype_line_starts(source)
  b.bench(() => b.keep(prototype_stateless_replay_workload(source, positions)))
}
