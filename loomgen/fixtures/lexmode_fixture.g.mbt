///|
pub(all) enum LexMode {
  Leaf
  Inline
  LineStart
} derive(Eq, Debug)

///|
pub fn lexmode_for_kind(kind : SyntaxKind) -> LexMode? {
  match kind {
    VarRef | IntLiteral => Some(Leaf)
    IfExpr | LetDef | AppExpr | ParamList | ParenExpr | TypeAnnot | TypeArrow | BinaryExpr | LambdaExpr => Some(Inline)
    SourceFile => Some(LineStart)
    _ => None
  }
}
