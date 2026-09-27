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

///|
pub extend SyntaxKind with @dowdiness/seam.ToRawKind::{to_raw}

///|
pub extend SyntaxKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SyntaxKind with Eq::{equal, not_equal}
