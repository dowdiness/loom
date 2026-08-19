///|
/// Session-owned Markdown lexer shell for reusable Markdown lexing.
///
/// The pure source-fact and replay functions remain in the existing Markdown
/// functional core. This shell owns only derived state and cache lifecycle.
pub struct MarkdownLexSession {
  priv detached_cache : Ref[DetachedCodeBlockIndentCache?]
  priv same_line_cache : Ref[SameLineListItemPrefixFacts?]
  priv source_ref : Ref[String?]
  priv line_end_cache_start : Ref[Int]
  priv line_end_cache_end : Ref[Int]
  priv opening_indent : Ref[Int?]
  priv continuation_pos : Ref[Int?]
  priv continuation_fence_length : Ref[Int?]
  priv continuation_fence_character : Ref[Char?]
}

///|
/// Construct an empty session with an explicit ownership boundary.
pub fn MarkdownLexSession::MarkdownLexSession() -> MarkdownLexSession {
  {
    detached_cache: { val: None },
    same_line_cache: { val: None },
    source_ref: { val: None },
    line_end_cache_start: { val: -1 },
    line_end_cache_end: { val: -1 },
    opening_indent: { val: None },
    continuation_pos: { val: None },
    continuation_fence_length: { val: None },
    continuation_fence_character: { val: None },
  }
}

///|
pub fn MarkdownLexSession::reset(self : MarkdownLexSession) -> Unit {
  self.detached_cache.val = None
  self.same_line_cache.val = None
  self.source_ref.val = None
  self.line_end_cache_start.val = -1
  self.line_end_cache_end.val = -1
  self.opening_indent.val = None
  self.continuation_pos.val = None
  self.continuation_fence_length.val = None
  self.continuation_fence_character.val = None
}

///|
fn MarkdownLexSession::ensure_source(
  self : MarkdownLexSession,
  input : String,
) -> Unit {
  let same_source = match self.source_ref.val {
    Some(source) => physical_equal(source, input)
    None => false
  }
  if !same_source {
    self.source_ref.val = Some(input)
    self.detached_cache.val = None
    self.same_line_cache.val = None
    self.line_end_cache_start.val = -1
    self.line_end_cache_end.val = -1
    self.opening_indent.val = None
    self.continuation_pos.val = None
    self.continuation_fence_length.val = None
    self.continuation_fence_character.val = None
  }
}

///|
fn MarkdownLexSession::line_end_hint(
  self : MarkdownLexSession,
  input : String,
  pos : Int,
  mode : MarkdownLexMode,
) -> Int? {
  let should_cache_line_end = pos < input.length() &&
    (match mode {
      LineStart => char_at(input, pos) == Some('>')
      BlockQuoteLineStart => true
      _ => false
    })
  if !should_cache_line_end {
    return None
  }
  let cached_start = self.line_end_cache_start.val
  let cached_end = self.line_end_cache_end.val
  if pos >= cached_start && pos <= cached_end {
    Some(cached_end)
  } else {
    let line_end = find_line_end(input, pos)
    self.line_end_cache_start.val = pos
    self.line_end_cache_end.val = line_end
    Some(line_end)
  }
}

///|
fn MarkdownLexSession::detached_indent(
  self : MarkdownLexSession,
  input : String,
  pos : Int,
  fence_length : Int,
  fence_character : Char,
) -> Int {
  match self.detached_cache.val {
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
      self.detached_cache.val = Some(DetachedCodeBlockIndentCache::{
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
        self.detached_cache.val = Some(DetachedCodeBlockIndentCache::{
          source: input,
          fence_length,
          fence_character,
          opening_indent: indent,
          next_pos: pos,
          replay,
        })
      } else {
        self.detached_cache.val = None
      }
      indent
    }
  }
}

///|
fn MarkdownLexSession::remember_detached(
  self : MarkdownLexSession,
  input : String,
  fence_length : Int,
  fence_character : Char,
  opening_indent : Int,
  next_pos : Int,
) -> Unit {
  if input.length() > DETACHED_CODE_BLOCK_CACHE_MAX_SOURCE_LENGTH ||
    next_pos >= input.length() {
    self.detached_cache.val = None
    return
  }
  match self.detached_cache.val {
    Some(cache) if cache.fence_length == fence_length &&
      cache.fence_character == fence_character &&
      physical_equal(cache.source, input) =>
      self.detached_cache.val = Some(DetachedCodeBlockIndentCache::{
        source: cache.source,
        fence_length: cache.fence_length,
        fence_character: cache.fence_character,
        opening_indent,
        next_pos,
        replay: cache.replay,
      })
    _ =>
      self.detached_cache.val = Some(DetachedCodeBlockIndentCache::{
        source: input,
        fence_length,
        fence_character,
        opening_indent,
        next_pos,
        replay: source_fence_replay_initial(
          input, fence_length, fence_character,
        ),
      })
  }
}

///|
pub fn MarkdownLexSession::step(
  self : MarkdownLexSession,
  input : String,
  pos : Int,
  mode : MarkdownLexMode,
) -> (@core.LexStep[Token], MarkdownLexMode) {
  self.ensure_source(input)
  let detached_opening_indent = match mode {
    CodeBlock(fence_length, fence_character, _) =>
      match
        (
          self.opening_indent.val,
          self.continuation_pos.val,
          self.continuation_fence_length.val,
          self.continuation_fence_character.val,
        ) {
        (
          Some(indent),
          Some(next_pos),
          Some(previous_length),
          Some(previous_character),
        ) if pos == next_pos &&
          fence_length == previous_length &&
          fence_character == previous_character => Some(indent)
        _ =>
          Some(self.detached_indent(input, pos, fence_length, fence_character))
      }
    _ => None
  }
  let line_end_hint = self.line_end_hint(input, pos, mode)
  let (step, next_mode) = markdown_lex_step_inner_with_context(
    input,
    pos,
    mode,
    line_end_hint,
    detached_opening_indent,
    Some(self.same_line_cache),
  )
  let next_pos = next_lex_step_offset(step, input)
  match next_mode {
    CodeBlock(fence_length, fence_character, _) => {
      let indent = match mode {
        CodeBlock(_, _, _) => detached_opening_indent.unwrap_or(0)
        _ => visual_column_at_offset(input, pos)
      }
      self.remember_detached(
        input, fence_length, fence_character, indent, next_pos,
      )
      self.opening_indent.val = Some(indent)
      self.continuation_pos.val = Some(next_pos)
      self.continuation_fence_length.val = Some(fence_length)
      self.continuation_fence_character.val = Some(fence_character)
    }
    _ => {
      self.detached_cache.val = None
      self.opening_indent.val = None
      self.continuation_pos.val = None
      self.continuation_fence_length.val = None
      self.continuation_fence_character.val = None
    }
  }
  if next_pos >= input.length() {
    self.same_line_cache.val = None
  }
  (step, next_mode)
}
