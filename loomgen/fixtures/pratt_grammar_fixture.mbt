/// Fixture for #601 Pratt EBNF: `@prefix`, `@prec`, `@skip` lowering to
/// `PrattApp` / `PrattBinary` without an outer `Node` wrapper.

#loom.token
pub(all) enum PrattTok {
  #loom.punct("i")
  Id
  #loom.punct("+")
  Plus
  #loom.punct("-")
  Minus
  #loom.punct("n")
  Newline
  #loom.eof
  Eof
} derive(Eq, Debug)

#loom.term
pub(all) enum PrattTerm {
  #loom.root
  #loom.rule("Expression")
  Source
  #loom.node
  #loom.rule("BinaryExpr")
  Expression
  #loom.node
  #loom.rule("@prefix AppExpr @prec[Plus, Minus] @skip(Newline)")
  BinaryExpr
  #loom.node
  #loom.rule("@prefix Atom")
  AppExpr
  #loom.node
  #loom.rule("Id")
  Atom
} derive(Eq, Debug)
