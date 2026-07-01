/// Fixture for #523 file-only mode: a #loom.term enum that carries ONLY roles and
/// NO #loom.rule annotations. Every production body comes from
/// `file_only.loomgrammar`, so this exercises the path that the annotation-mode
/// fixtures cannot — emission gated on the file-supplied rules, multi-production
/// output, a cross-rule `Ref` (Pair -> Inner), and a root designated by
/// #loom.root but bodied entirely by the file.

#loom.token
pub(all) enum FTok {
  #loom.punct("(")
  LParen
  #loom.punct(")")
  RParen
  #loom.punct(",")
  Comma
  #loom.error
  Error(String)
  #loom.eof
  Eof
} derive(Eq, Debug)

#loom.term
pub(all) enum FTerm {
  #loom.root
  Pair
  #loom.node
  Inner
} derive(Eq, Debug)
