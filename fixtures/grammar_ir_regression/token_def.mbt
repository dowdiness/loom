///|
pub(all) enum Token {
  A
  B
  Eof
} derive(Eq, Debug)

///|
pub impl Show for Token with fn output(self, logger) {
  logger.write_string(
    match self {
      A => "A"
      B => "B"
      Eof => "Eof"
    },
  )
}

///|
pub impl @seam.IsTrivia for Token with fn is_trivia(_self) {
  false
}

///|
pub impl @seam.IsEof for Token with fn is_eof(self) {
  self == Eof
}

///|
pub impl @seam.ToRawKind for Token with fn to_raw(self) {
  match self {
    A => @seam.RawKind(0)
    B => @seam.RawKind(1)
    Eof => @seam.RawKind(2)
  }
}
