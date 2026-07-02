///|
/// Term kind metadata for loomgen Phase 2 generation of the lambda example.
/// Contains the #loom.term enum defining CST node types that appear in SyntaxKind.
/// This is the single source of truth for CST term-kind metadata; the token enum
/// lives in examples/lambda/token/token.mbt.
///
/// NOT part of any package — consumed by loomgen at generation time via --term.
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
  #loom.leaf
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
  #loom.node
  BlockExpr
  #loom.leaf
  HoleLiteral
  #loom.node
  TypeAnnot
  #loom.leaf
  TypeInt
  #loom.leaf
  TypeUnit
  #loom.node
  TypeArrow
  #loom.node
  IfCondition
  #loom.node
  IfThen
  #loom.node
  IfElse
  #loom.node
  LambdaBody
}
