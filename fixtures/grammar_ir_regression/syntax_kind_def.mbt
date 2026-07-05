///|
pub(all) enum SyntaxKind {
  Start
  AToken
  BToken
} derive(Eq, Debug)

///|
pub impl @seam.ToRawKind for SyntaxKind with fn to_raw(self) {
  match self {
    Start => @seam.RawKind(10)
    AToken => @seam.RawKind(11)
    BToken => @seam.RawKind(12)
  }
}
