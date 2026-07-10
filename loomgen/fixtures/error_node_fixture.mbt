/// Fixture for #605 @error_node(Kind, Token) EBNF syntax.
/// Exercises single-token sync within a Choice with catch-all treatment.

#loom.token
pub(all) enum Tok {
  #loom.punct(";")
  Semicolon
  #loom.keyword("x")
  X
  #loom.keyword("y")
  Y
  #loom.keyword("if")
  If
  #loom.error
  Error(String)
  #loom.eof
  Eof
} derive(Eq, Debug)

#loom.term
pub(all) enum ErrTerm {
  #loom.errornode
  ErrorNode
  #loom.root
  #loom.rule("(X | @error_node(ErrorNode, Semicolon)) Eof")
  Source
} derive(Eq, Debug)
