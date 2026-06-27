///|
/// View annotation fixture for loomgen Phase 3 testing.
/// Contains both #loom.token and #loom.term enums with #loom.view variants.
/// Used for regression testing of emit_view_accessors.

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
  IfExpr
  #loom.view("IfExpr", "condition")
  IfCondition
  #loom.view("IfExpr", "then_branch")
  IfThen
  #loom.view("IfExpr", "else_branch", "optional")
  IfElse
  #loom.node
  AppExpr
  #loom.node
  BinaryExpr
  #loom.node
  ParenExpr
  #loom.leaf
  IntLiteral
  #loom.leaf
  VarRef
  #loom.view("LambdaExpr", "body")
  LambdaBody
  #loom.errornode
  ErrorNode
  #loom.root
  SourceFile
}
