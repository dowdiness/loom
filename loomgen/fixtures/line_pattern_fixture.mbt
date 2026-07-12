/// Fixture for #561 line lexer generation.
/// Exercises #loom.line_pattern on block-level token variants and
/// #loom.line_mode on term variants with #loom.lexmode.
/// Note: regex alternation is not supported in line_pattern (leftmost-match
/// vs longest-match conflict), so each pattern must be unambiguous.
/// The generated code wraps patterns in `^(?:...)` so patterns should not
/// include their own `^` anchor.

#loom.token
pub(all) enum Token {
  #loom.line_pattern("#{1,6} ")
  #loom.custom_lex("lex_heading_marker")
  HeadingMarker(Int)
  #loom.line_pattern("\\- ")
  ListMarkerDash
  #loom.line_pattern("\\* ")
  ListMarkerStar
  #loom.line_pattern("\\+ ")
  ListMarkerPlus
  #loom.line_pattern("--- ")
  ThematicBreak
  #loom.line_pattern(">")
  BlockQuoteMarker
  #loom.error
  Error(String)
  #loom.eof
  EOF
} derive(Eq, Debug)

#loom.term
pub(all) enum Term {
  #loom.leaf
  #loom.lexmode("LineStart")
  #loom.line_mode
  #loom.fallback_lex("lex_inline")
  Heading
  #loom.leaf
  #loom.lexmode("LineStart")
  #loom.line_mode
  ListItem
  #loom.leaf
  #loom.lexmode("Inline")
  Text
  #loom.root
  Root
  #loom.errornode
  ErrorNode
} derive(Eq, Debug)
