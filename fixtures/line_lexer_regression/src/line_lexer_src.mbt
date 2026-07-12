///|
#loom.token
pub(all) enum Token {
  #loom.line_pattern("#{1,6} ")
  #loom.custom_lex("lex_heading_marker")
  HeadingMarker(Int)
  #loom.line_pattern("- ")
  ListMarker
  #loom.line_pattern(">")
  BlockQuoteMarker
  #loom.ident
  Text(String)
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
  Block
  #loom.leaf
  #loom.lexmode("Inline")
  Inline
  #loom.root
  Root
  #loom.errornode
  ErrorNode
} derive(Eq, Debug)
