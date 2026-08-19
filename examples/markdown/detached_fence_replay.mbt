///|
const DETACHED_CODE_BLOCK_CACHE_MAX_SOURCE_LENGTH : Int = 1024 * 1024

///|
/// Stateful source replay for detached CodeBlock mode. The normal mode lexer
/// already carries the opening indentation; this adapter only reconstructs it
/// when a caller starts stepping in the middle of a source.
priv struct SourceFenceReplayState {
  source : String
  fence_length : Int
  fence_character : Char
  scan_pos : Int
  active : (Int, Char, Int)?
}

///|
fn source_fence_replay_initial(
  input : String,
  fence_length : Int,
  fence_character : Char,
) -> SourceFenceReplayState {
  SourceFenceReplayState::{
    source: input,
    fence_length,
    fence_character,
    scan_pos: 0,
    active: None,
  }
}

///|
fn source_fence_active(
  input : String,
  line_start : Int,
  fence_character : Char,
  candidate : SourceFenceCandidate,
) -> (Int, Char, Int) {
  (
    candidate.run_len,
    fence_character,
    count_indent_columns(input, line_start, candidate.marker_start),
  )
}

///|
fn source_fence_replay_advance_line(
  state : SourceFenceReplayState,
  line_start : Int,
  line_end : Int,
) -> (Int, Char, Int)? {
  match state.active {
    None =>
      match
        source_fence_candidate(
          state.source,
          line_start,
          line_end,
          state.fence_length,
          state.fence_character,
        ) {
        Some(candidate) =>
          Some(
            source_fence_active(
              state.source,
              line_start,
              state.fence_character,
              candidate,
            ),
          )
        None => None
      }
    Some((open_len, open_character, opening_indent)) =>
      if source_code_block_close_candidate(
          state.source,
          line_start,
          open_len,
          open_character,
          opening_indent,
        ) {
        None
      } else {
        state.active
      }
  }
}

///|
/// Advance through complete source lines and return the fence ownership at
/// `pos`. The current line is observed before its closing fence is committed,
/// matching the detached lexer contract for a CodeBlock step.
fn source_fence_replay_until(
  state : SourceFenceReplayState,
  pos : Int,
) -> (SourceFenceReplayState, Int?) {
  let current_line_start = line_start_offset(state.source, pos)
  let base = if state.scan_pos > current_line_start {
    source_fence_replay_initial(
      state.source,
      state.fence_length,
      state.fence_character,
    )
  } else {
    state
  }
  let mut scan = base.scan_pos
  let mut active = base.active
  while scan < current_line_start {
    let line_end = find_line_end(base.source, scan)
    let next_active = source_fence_replay_advance_line(
      SourceFenceReplayState::{
        source: base.source,
        fence_length: base.fence_length,
        fence_character: base.fence_character,
        scan_pos: scan,
        active,
      },
      scan,
      line_end,
    )
    active = next_active
    let next = line_end_including_break(base.source, line_end)
    if next <= scan {
      break
    }
    scan = next
  }
  let line_end = find_line_end(base.source, current_line_start)
  let opening_active = match active {
    Some(_) => active
    None =>
      match
        source_fence_candidate(
          base.source,
          current_line_start,
          line_end,
          base.fence_length,
          base.fence_character,
        ) {
        Some(candidate) if candidate.marker_start <= pos =>
          Some(
            source_fence_active(
              base.source,
              current_line_start,
              base.fence_character,
              candidate,
            ),
          )
        _ => None
      }
  }
  let opening_indent = match opening_active {
    Some((open_len, open_character, opening_indent)) if open_len ==
      base.fence_length &&
      open_character == base.fence_character => Some(opening_indent)
    _ => None
  }
  let next_active = source_fence_replay_advance_line(
    SourceFenceReplayState::{
      source: base.source,
      fence_length: base.fence_length,
      fence_character: base.fence_character,
      scan_pos: current_line_start,
      active,
    },
    current_line_start,
    line_end,
  )
  let next_scan = line_end_including_break(base.source, line_end)
  let next_state = SourceFenceReplayState::{
    source: base.source,
    fence_length: base.fence_length,
    fence_character: base.fence_character,
    scan_pos: if next_scan > current_line_start {
      next_scan
    } else {
      current_line_start
    },
    active: next_active,
  }
  (next_state, opening_indent)
}

///|
/// Stateless compatibility wrapper used by the stateful mode lexer when it
/// has no opening-column context yet.
fn source_derived_code_block_indent(
  input : String,
  pos : Int,
  fence_len : Int,
  fence_character : Char,
) -> Int? {
  let state = source_fence_replay_initial(input, fence_len, fence_character)
  source_fence_replay_until(state, pos).1
}

///|
priv struct DetachedCodeBlockIndentCache {
  source : String
  fence_length : Int
  fence_character : Char
  opening_indent : Int
  next_pos : Int
  replay : SourceFenceReplayState
}
