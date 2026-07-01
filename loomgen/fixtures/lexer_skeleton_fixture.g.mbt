///|
/// Generated lex dispatch skeleton.
/// Fill in the mode-specific `lex_*` functions below.
pub fn lex(
  source : String,
  pos : Int,
  mode : LexMode,
) -> (@core.LexStep[Token], LexMode) {
  match mode {
    Leaf => lex_leaf(source, pos)
    Inline => lex_inline(source, pos)
    LineStart => lex_line_start(source, pos)
  }
}

fn lex_leaf(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {
  abort("lex_leaf not implemented")
}

fn lex_inline(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {
  abort("lex_inline not implemented")
}

fn lex_line_start(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {
  abort("lex_line_start not implemented")
}
