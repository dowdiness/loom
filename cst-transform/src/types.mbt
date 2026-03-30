///|
pub(all) enum TokenKind {
  Ident
  Number
  LParen
  RParen
  Plus
  Minus
  Star
  Slash
  Eq
  Let
  Fn_
  Whitespace
  Newline
  Eof
} derive(Eq, Show, Hash, Compare)

///|
pub(all) enum SyntaxKind {
  SourceFile
  FnDef
  LetStmt
  BinaryExpr
  CallExpr
  ParenExpr
  ArgList
  Literal
  Name
  Error
} derive(Eq, Show, Hash, Compare)

///|
pub(all) enum GreenNode {
  Leaf(TokenKind, String)
  Branch(SyntaxKind, Array[GreenNode])
} derive(Eq, Show)
