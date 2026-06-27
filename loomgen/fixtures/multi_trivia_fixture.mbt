///|
/// Multi-trivia fixture: token enum with two #loom.trivia variants.
/// Used to verify is_*_trivia_kind helper generation in spec.g.mbt.

#loom.token
pub(all) enum MultiTriviaToken {
  #loom.trivia
  Whitespace
  #loom.trivia
  Comment
  #loom.error
  Error(String)
  #loom.eof
  EOF
} derive(Eq, Debug)

#loom.term
pub(all) enum MultiTriviaSyntaxKind {
  #loom.node
  Element
  #loom.errornode
  ErrorNode
  #loom.root
  SourceFile
} derive(Eq, Debug)
