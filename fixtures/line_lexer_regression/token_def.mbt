///|
pub(all) enum Token {
  HeadingMarker(Int)
  ListMarker
  BlockQuoteMarker
  Text(String)
  BlankLine
  Error(String)
  EOF
} derive(Eq, Debug)

///|
pub extend Token with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Token with Eq::{equal, not_equal}
