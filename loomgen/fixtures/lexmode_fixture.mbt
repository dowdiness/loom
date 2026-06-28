///|
/// Fixture for #loom.lexmode annotation modifiers on term variants.
/// Tests multiple modes and shared-mode grouping.
/// Based on term_kind.mbt with lexmode annotations added to selected variants.

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
  #loom.node #loom.lexmode("LineStart")
  SourceFile
  #loom.node #loom.lexmode("Inline")
  LambdaExpr
  #loom.node #loom.lexmode("Inline")
  AppExpr
  #loom.node #loom.lexmode("Inline")
  BinaryExpr
  #loom.node #loom.lexmode("Inline")
  IfExpr
  #loom.node #loom.lexmode("Inline")
  ParenExpr
  #loom.leaf #loom.lexmode("Leaf")
  IntLiteral
  #loom.leaf #loom.lexmode("Leaf")
  VarRef
  #loom.errornode
  ErrorNode
  #loom.node #loom.lexmode("Inline")
  LetDef
  #loom.node #loom.lexmode("Inline")
  ParamList
  #loom.leaf
  HoleLiteral
  #loom.node #loom.lexmode("Inline")
  TypeAnnot
  #loom.leaf
  TypeInt
  #loom.leaf
  TypeUnit
  #loom.node #loom.lexmode("Inline")
  TypeArrow
}
