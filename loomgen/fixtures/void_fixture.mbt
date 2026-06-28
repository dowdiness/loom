///|
/// Fixture for #loom.void and #loom.rawtext term annotation modifiers.
/// Based on term_kind.mbt with void/rawtext added to selected variants.
/// Annotations must be on separate lines (MoonBit parser constraint).
/// Keeps token enum pristine (no modifiers) for CI compatibility.

#loom.token
pub(all) enum Token {
  #loom.punct("λ")
  Lambda
  #loom.punct(".")
  Dot
  #loom.punct("(")
  LeftParen
  #loom.punct(")")
  RightParen
  #loom.punct("+")
  Plus
  #loom.punct("-")
  Minus
  #loom.keyword("if")
  If
  #loom.keyword("then")
  Then
  #loom.keyword("else")
  Else
  #loom.keyword("fn")
  Fn
  #loom.keyword("let")
  Let
  #loom.punct("=")
  Eq
  #loom.punct("{")
  LBrace
  #loom.punct("}")
  RBrace
  #loom.punct(",")
  Comma
  #loom.punct(";")
  Semicolon
  #loom.punct(":")
  Colon
  #loom.punct("->")
  Arrow
  #loom.punct("=>")
  FatArrow
  #loom.punct("_")
  Hole
  #loom.ident
  Identifier
  #loom.literal("IntToken")
  Integer
  #loom.trivia
  Whitespace
  #loom.delimiter
  Newline
  #loom.error
  Error(String)
  #loom.eof
  EOF
} derive(Eq, Debug)

#loom.term
pub(all) enum TermKind {
  #loom.node
  LambdaExpr
  #loom.node
  AppExpr
  #loom.node
  BinaryExpr
  #loom.node
  IfExpr
  #loom.node
  ParenExpr
  #loom.rawtext #loom.leaf
  IntLiteral
  #loom.leaf
  VarRef
  #loom.errornode
  ErrorNode
  #loom.root
  SourceFile
  #loom.node
  LetDef
  #loom.node
  ParamList
  #loom.void #loom.leaf
  HoleLiteral
  #loom.node
  TypeAnnot
  #loom.leaf
  TypeInt
  #loom.leaf
  TypeUnit
  #loom.node
  TypeArrow
}
