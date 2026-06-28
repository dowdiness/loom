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
pub impl @core.AstView for IfExprProj with fn syntax_node(self) {
  self.node
}

///|
pub fn IfExprProj::condition(
  self : IfExprProj,
  message? : String = "view IfExpr.condition expects exactly one IfCondition",
) -> Result[@seam.SyntaxNode, @seam.ProjectionShapeError] {
  self.node.required_direct_child_of_kind(IfCondition.to_raw(), message~)
}

///|
pub fn IfExprProj::then_branch(
  self : IfExprProj,
  message? : String = "view IfExpr.then_branch expects exactly one IfThen",
) -> Result[@seam.SyntaxNode, @seam.ProjectionShapeError] {
  self.node.required_direct_child_of_kind(IfThen.to_raw(), message~)
}

///|
pub fn IfExprProj::else_branch(
  self : IfExprProj,
  message? : String = "view IfExpr.else_branch expects at most one IfElse",
) -> Result[@seam.SyntaxNode?, @seam.ProjectionShapeError] {
  self.node.optional_direct_child_of_kind(IfElse.to_raw(), message~)
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
pub impl @core.AstView for LambdaExprProj with fn syntax_node(self) {
  self.node
}

///|
pub fn LambdaExprProj::body(
  self : LambdaExprProj,
  message? : String = "view LambdaExpr.body expects exactly one LambdaBody",
) -> Result[@seam.SyntaxNode, @seam.ProjectionShapeError] {
  self.node.required_direct_child_of_kind(LambdaBody.to_raw(), message~)
}

///|
pub struct IfConditionProj {
  node : @seam.SyntaxNode
}

///|
pub fn IfConditionProj::cast(n : @seam.SyntaxNode) -> IfConditionProj? {
  if SyntaxKind::from_raw(n.kind()) == IfCondition {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @core.AstView for IfConditionProj with fn syntax_node(self) {
  self.node
}

///|
pub struct LambdaBodyProj {
  node : @seam.SyntaxNode
}

///|
pub fn LambdaBodyProj::cast(n : @seam.SyntaxNode) -> LambdaBodyProj? {
  if SyntaxKind::from_raw(n.kind()) == LambdaBody {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @core.AstView for LambdaBodyProj with fn syntax_node(self) {
  self.node
}

///|
/// Return the single expression/block child wrapped by this LambdaBody.
pub fn LambdaBodyProj::inner(
  self : LambdaBodyProj,
  message? : String = "view LambdaBody.inner expects exactly one child expression",
) -> Result[@seam.SyntaxNode, @seam.ProjectionShapeError] {
  match self.node.nth_child(0) {
    Some(child) => Ok(child)
    None =>
      Err(
        @seam.ProjectionShapeError::ProjectionShapeError(
          self.node,
          LambdaBody.to_raw(),
          @seam.ProjectionShapeElement::ChildElement,
          @seam.ProjectionShapeExpectation::ExpectedOne,
          0,
          self.node.start(),
          self.node.end(),
          message~,
        ),
      )
  }
}

///|
pub struct BlockExprProj {
  node : @seam.SyntaxNode
}

///|
pub fn BlockExprProj::cast(n : @seam.SyntaxNode) -> BlockExprProj? {
  if SyntaxKind::from_raw(n.kind()) == BlockExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @core.AstView for BlockExprProj with fn syntax_node(self) {
  self.node
}

///|
pub fn BlockExprProj::defs(self : BlockExprProj) -> Array[@seam.SyntaxNode] {
  self.node.direct_children_of_kind(LetDef.to_raw())
}
