///|
pub impl Show for Token with fn output(self, logger) {
  logger.write_string(
    match self {
      HeadingMarker(_) => "<int>"
      EOF => "EOF"
    },
  )
}

///|
pub impl @seam.IsTrivia for Token with fn is_trivia(self) {
  false
}

///|
pub impl @seam.IsEof for Token with fn is_eof(self) {
  match self {
    EOF => true
    _ => false
  }
}

///|
/// Maps tokens to the same raw-kind space as SyntaxKind.
pub impl @seam.ToRawKind for Token with fn to_raw(self) {
  let n : Int = match self {
    HeadingMarker(_) => 0
    EOF => 1
  }
  @seam.RawKind(n)
}
