/// Fixture for #522 GrammarIr generation. Covers notation parsing, identifier
/// resolution, Node wrapping, Expect lowering, and ExpectSkip (~>).

///|
#loom.token
pub(all) enum Tok {
  #loom.punct("(")
  LParen
  #loom.punct(")")
  RParen
  #loom.punct("\n")
  Newline
  #loom.error
  Error(String)
  #loom.eof
  Eof
} derive(Eq, Debug)

#loom.term
pub(all) enum MiniTerm {
  #loom.root
  #loom.rule("Newline~>LParen RParen")
  Parens
} derive(Eq, Debug)
