/// Fixture for #522 GrammarIr generation. Smallest case: one #loom.root
/// production over two punctuation terminals. No alternation or repetition, so
/// it exercises notation parsing, identifier resolution, Node wrapping, and
/// Expect lowering — but NO FIRST-set logic (that is covered by later fixtures).

#loom.token
pub(all) enum Tok {
  #loom.punct("(")
  LParen
  #loom.punct(")")
  RParen
  #loom.error
  Error(String)
  #loom.eof
  Eof
} derive(Eq, Debug)

#loom.term
pub(all) enum MiniTerm {
  #loom.root
  #loom.rule("LParen RParen")
  Parens
} derive(Eq, Debug)
