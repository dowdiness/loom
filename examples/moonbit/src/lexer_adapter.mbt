///|
/// Lex MoonBit source with the official `moonbitlang/parser` lexer and adapt it
/// to Loom's position-independent token stream.
///
/// This is the first integration seam for the full project: keep official
/// tokenization/ASI behavior, then incrementally replace the parser layer with
/// Loom CST rules.
pub fn lex_moonbit(
  source : String,
  name? : String = "",
) -> @core.LexResult[MoonToken] {
  let official = @lexer.tokens_from_string_with_utf16_location(
    source,
    comment=true,
    name~,
  )
  let tokens : Array[@core.TokenInfo[MoonToken]] = []
  let starts : Array[Int] = []
  let diagnostics = @core.DiagnosticSet::empty()
  for error in official.errors {
    let (start_pos, end_pos, err) = error
    diagnostics.push(
      @core.Diagnostic::lexer_error_at(
        err.to_string(),
        start_pos.cnum,
        end_pos.cnum,
        "moonbitlang/parser/lexer",
      ),
    )
  }
  let source_len = source.length()
  let cursor = for triple in official.tokens; cursor = 0 {
    let (official_token, start_pos, end_pos) = triple
    let start = clamp_offset(start_pos.cnum, source_len)
    let end = clamp_offset(end_pos.cnum, source_len)
    if start > cursor {
      push_loom_token(
        tokens,
        starts,
        cursor,
        start,
        gap_token(source, cursor, start),
      )
    }
    push_loom_token(
      tokens,
      starts,
      start,
      end,
      MoonToken::from_official(official_token),
    )
    continue if end > cursor { end } else { cursor }
  } nobreak {
    cursor
  }
  if cursor < source_len {
    push_loom_token(
      tokens,
      starts,
      cursor,
      source_len,
      gap_token(source, cursor, source_len),
    )
  }
  @core.LexResult::with_starts(tokens, starts, diagnostics~)
}

///|
pub fn tokenize(source : String) -> Array[@core.TokenInfo[MoonToken]] {
  lex_moonbit(source).tokens()
}

///|
fn push_loom_token(
  tokens : Array[@core.TokenInfo[MoonToken]],
  starts : Array[Int],
  start : Int,
  end : Int,
  token : MoonToken,
) -> Unit {
  starts.push(start)
  tokens.push(@core.TokenInfo::new(token, end - start))
}

///|
fn gap_token(source : String, start : Int, end : Int) -> MoonToken {
  if source.view(start_offset=start, end_offset=end).is_blank() {
    Whitespace
  } else {
    Error("unlexed source")
  }
}

///|
fn clamp_offset(offset : Int, source_len : Int) -> Int {
  if offset < 0 {
    0
  } else if offset > source_len {
    source_len
  } else {
    offset
  }
}
