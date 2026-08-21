///|
/// Lex MoonBit source with the official `moonbitlang/parser` lexer and adapt it
/// to Loom's position-independent token stream.
///
/// This is the first integration seam for the full project: keep official
/// tokenization/ASI behavior, then incrementally replace the parser layer with
/// Loom CST rules.
pub fn lex_moonbit(
  source_id : @core.SourceId,
  source : String,
  name? : String = "",
) -> @core.LexResult[MoonToken] {
  let official = @lexer.tokens_from_string_with_utf16_location(
    source,
    comment=true,
    name~,
  )
  let located_tokens : Array[@core.LocatedToken[MoonToken]] = []
  let diagnostics = @core.DiagnosticSet::empty()
  for error in official.errors {
    let (start_pos, end_pos, err) = error
    diagnostics.push(
      @core.lexer_diagnostic_at(
        source_id,
        err.to_string(),
        start_pos.cnum,
        end_pos.cnum,
        "moonbitlang/lexer",
      ),
    )
  }
  for triple in official.tokens {
    let (official_token, start_pos, end_pos) = triple
    located_tokens.push(
      @core.LocatedToken::LocatedToken(
        MoonToken::from_official(official_token),
        start=start_pos.cnum,
        end=end_pos.cnum,
      ),
    )
  }
  @core.LexResult::from_located_tokens(
    source_id,
    source,
    located_tokens,
    gap_token=fn(_text, _start, _end) { Whitespace },
    gap_error_token=fn(_text, _start, _end) { Error("unlexed source") },
    diagnostics~,
    diagnose_nonblank_gaps=false,
  )
}

///|
pub fn tokenize(
  source_id : @core.SourceId,
  source : String,
) -> Array[@core.TokenInfo[MoonToken]] {
  lex_moonbit(source_id, source).tokens()
}
