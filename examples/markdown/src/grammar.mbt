///|
let mode_state : @core.ModeRelexState[Token] = @core.erase_mode_lexer(
  markdown_mode_lexer,
  EOF,
)

///|
fn lex_for_grammar(source : String) -> @core.LexResult[Token] {
  let result : Result[
    (Array[@core.TokenInfo[Token]], Array[Int]),
    @core.LexError,
  ] = try? (mode_state.tokenize)(source)
  match result {
    Ok((tokens, starts)) =>
      @core.LexResult::with_starts(
        tokens,
        starts,
        diagnostics=@core.DiagnosticSet::empty(),
      )
    Err(@core.LexError(msg)) =>
      @core.LexResult::with_starts(
        [
          @core.TokenInfo::new(Error(msg), source.length()),
          @core.TokenInfo::new(EOF, 0),
        ],
        [0, source.length()],
        diagnostics=@core.DiagnosticSet::single(
          @core.Diagnostic::lexer_error_at(
            msg,
            0,
            source.length(),
            "lex-error",
          ),
        ),
      )
  }
}

///|
pub let markdown_grammar : @loom.Grammar[Token, SyntaxKind, Block] = @loom.Grammar::new(
  spec=markdown_spec,
  lex=lex_for_grammar,
  fold_node=markdown_fold_node,
  on_lex_error=fn(msg) { Block::Error("lex error: " + msg) },
  mode_relex=Some(mode_state),
)
