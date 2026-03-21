// term_convert.mbt — SyntaxNode → Term conversion via typed views.

///|
/// Algebra for CstFold: per-node conversion with framework-managed recursion.
/// Handles both SourceFile (LetDef* Expression?) and single expressions.
pub fn lambda_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> @ast.Term,
) -> @ast.Term {
  match @syntax.SyntaxKind::from_raw(node.kind()) {
    @syntax.SourceFile => {
      let items : Array[@ast.ModuleItem] = []
      let mut has_defs = false
      let mut got_expr = false
      for child in node.children() {
        match @syntax.SyntaxKind::from_raw(child.kind()) {
          @syntax.LetDef => {
            has_defs = true
            got_expr = false // allow next expr after a def
            let v = LetDefView::{ node: child }
            let init = match v.init() {
              Some(expr_node) => recurse(expr_node)
              None => @ast.Term::Error("missing LetDef init")
            }
            items.push(@ast.ModuleItem::Def(v.name(), init))
          }
          _ =>
            // Take only the first expression after each def group.
            // Incremental CST reuse can produce extra expression children;
            // taking only the first keeps parity with a full reparse.
            if not(got_expr) {
              got_expr = true
              items.push(@ast.ModuleItem::Expr(recurse(child)))
            }
        }
      }
      if items.length() == 1 {
        match items[0] {
          @ast.ModuleItem::Expr(expr) => expr
          _ => @ast.Term::Module(items)
        }
      } else if items.is_empty() {
        @ast.Term::Unit
      } else if not(has_defs) {
        // Expression-only: unwrap
        match items[0] {
          @ast.ModuleItem::Expr(expr) => expr
          _ => @ast.Term::Unit
        }
      } else {
        @ast.Term::Module(items)
      }
    }
    _ => fold_node_inner(node, recurse)
  }
}

///|
fn fold_node_inner(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> @ast.Term,
) -> @ast.Term {
  match @syntax.SyntaxKind::from_raw(node.kind()) {
    @syntax.IntLiteral => {
      let v = IntLiteralView::{ node, }
      @ast.Term::Int(v.value().unwrap_or(0))
    }
    @syntax.VarRef => {
      let v = VarRefView::{ node, }
      @ast.Term::Var(v.name())
    }
    @syntax.LambdaExpr => {
      let v = LambdaExprView::{ node, }
      let body = match v.body() {
        Some(b) => recurse(b)
        None => @ast.Term::Error("missing lambda body")
      }
      @ast.Term::Lam(v.param(), body)
    }
    @syntax.AppExpr => {
      let v = AppExprView::{ node, }
      match v.func() {
        None => @ast.Term::Error("missing function in application")
        Some(func_node) => {
          let mut result = recurse(func_node)
          for arg in v.args() {
            result = @ast.Term::App(result, recurse(arg))
          }
          result
        }
      }
    }
    @syntax.BinaryExpr => {
      let (children, all_tokens) = node.nodes_and_tokens()
      let ops : Array[@ast.Bop] = []
      for t in all_tokens {
        if t.kind() == @syntax.PlusToken.to_raw() {
          ops.push(@ast.Bop::Plus)
        } else if t.kind() == @syntax.MinusToken.to_raw() {
          ops.push(@ast.Bop::Minus)
        }
      }
      if children.length() >= 2 {
        let mut result = recurse(children[0])
        for i = 1; i < children.length(); i = i + 1 {
          let op = if i - 1 < ops.length() {
            ops[i - 1]
          } else {
            @ast.Bop::Plus
          }
          result = @ast.Term::Bop(op, result, recurse(children[i]))
        }
        result
      } else if children.length() == 1 {
        recurse(children[0])
      } else {
        @ast.Term::Error("empty BinaryExpr")
      }
    }
    @syntax.IfExpr => {
      let v = IfExprView::{ node, }
      let cond = match v.condition() {
        Some(n) => recurse(n)
        None => @ast.Term::Error("missing if condition")
      }
      let then_ = match v.then_branch() {
        Some(n) => recurse(n)
        None => @ast.Term::Error("missing then branch")
      }
      let else_ = match v.else_branch() {
        Some(n) => recurse(n)
        None => @ast.Term::Error("missing else branch")
      }
      @ast.Term::If(cond, then_, else_)
    }
    @syntax.ParenExpr => {
      let v = ParenExprView::{ node, }
      match v.inner() {
        Some(inner) => recurse(inner)
        None => @ast.Term::Error("empty parentheses")
      }
    }
    @syntax.ErrorNode => @ast.Term::Error("ErrorNode")
    _ =>
      @ast.Term::Error(
        "unknown node kind: " +
        @syntax.SyntaxKind::from_raw(node.kind()).to_string(),
      )
  }
}

///|
/// Convenience wrapper: convert a SyntaxNode to Term without caching.
/// Delegates to lambda_fold_node with itself as the recursion function.
/// Used by tests that construct CSTs directly via parse_cst.
pub fn syntax_node_to_term(root : @seam.SyntaxNode) -> @ast.Term {
  lambda_fold_node(root, syntax_node_to_term)
}
