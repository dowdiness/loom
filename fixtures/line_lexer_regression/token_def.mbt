///|
#derive(Eq, Debug)
pub(all) enum Token {
  HeadingMarker(Int32)
  ListMarker
  BlockQuoteMarker
  Text(String)
  BlankLine
  Error(String)
  EOF
}

///|
pub extend Token with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Token with Eq::{equal, not_equal}
