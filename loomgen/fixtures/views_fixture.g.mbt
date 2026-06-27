///|
/// Generated typed projection accessors from #loom.view annotations.

///|
pub struct IfExprProj {
  node : @seam.SyntaxNode
}

///|
pub fn IfExprProj::cast(n : @seam.SyntaxNode) -> IfExprProj? {
  if SyntaxKind::from_raw(n.kind()) == IfExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub fn IfExprProj::condition(
  self : IfExprProj,
  message? : String = "view IfExpr.condition expects exactly one IfCondition",
) -> Result[@seam.SyntaxNode, @seam.ProjectionShapeError] {
  self.node.required_direct_child_of_kind(IfCondition.to_raw(), message=message)
}

///|
pub fn IfExprProj::else_branch(
  self : IfExprProj,
  message? : String = "view IfExpr.else_branch expects at most one IfElse",
) -> Result[@seam.SyntaxNode?, @seam.ProjectionShapeError] {
  self.node.optional_direct_child_of_kind(IfElse.to_raw(), message=message)
}

///|
pub fn IfExprProj::then_branch(
  self : IfExprProj,
  message? : String = "view IfExpr.then_branch expects exactly one IfThen",
) -> Result[@seam.SyntaxNode, @seam.ProjectionShapeError] {
  self.node.required_direct_child_of_kind(IfThen.to_raw(), message=message)
}

///|
pub struct LambdaExprProj {
  node : @seam.SyntaxNode
}

///|
pub fn LambdaExprProj::cast(n : @seam.SyntaxNode) -> LambdaExprProj? {
  if SyntaxKind::from_raw(n.kind()) == LambdaExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub fn LambdaExprProj::body(
  self : LambdaExprProj,
  message? : String = "view LambdaExpr.body expects exactly one LambdaBody",
) -> Result[@seam.SyntaxNode, @seam.ProjectionShapeError] {
  self.node.required_direct_child_of_kind(LambdaBody.to_raw(), message=message)
}
