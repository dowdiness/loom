/// Fixture for M16 #598 ~ (Emit), #599 ! (EmitOr), #600 @until (ErrorUntil).
/// Exercises all three syntaxes in one production to keep the fixture count
/// minimal while testing each lowering path at least once.

#loom.token
pub(all) enum Tok {
  #loom.punct(";")
  Semicolon
  #loom.punct("{")
  LBrace
  #loom.punct("}")
  RBrace
  #loom.keyword("x")
  X
  #loom.error
  Error(String)
  #loom.eof
  Eof
} derive(Eq, Debug)

#loom.term
pub(all) enum EmitTerm {
  #loom.root
  #loom.rule("X~ X! @until(Semicolon)")
  Source
} derive(Eq, Debug)
