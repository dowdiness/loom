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
