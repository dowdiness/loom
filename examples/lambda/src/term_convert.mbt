// term_convert.mbt — SyntaxNode → Term conversion via typed views.

///|
/// Convert a LetDef CST node to (name, term) pair.
/// Applies ParamList desugaring: right-folds params into nested Lam.
fn convert_let_def(
  v : LetDefView,
  recurse : (@seam.SyntaxNode) -> @ast.Term,
) -> (@ast.VarName, @ast.Term) {
  let init = match v.init() {
    Some(expr_node) => recurse(expr_node)
    None => @ast.Term::Error("missing LetDef init")
  }
  let params = v.params()
  let mut body = init
  for i = params.length() - 1; i >= 0; i = i - 1 {
    body = @ast.Term::Lam(params[i], body)
  }
  (v.name(), body)
}

///|
/// Collect LetDef children and trailing expression from a node.
/// Used by both SourceFile and BlockExpr conversion.
fn collect_defs_and_body(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> @ast.Term,
) -> (Array[(@ast.VarName, @ast.Term)], @ast.Term) {
  let defs : Array[(@ast.VarName, @ast.Term)] = []
  let mut final_term : @ast.Term = @ast.Term::Unit
  for child in node.children() {
    match @syntax.SyntaxKind::from_raw(child.kind()) {
      @syntax.LetDef => {
        let v = LetDefView::{ node: child }
        let (name, body) = convert_let_def(v, recurse)
        defs.push((name, body))
      }
      _ => if final_term == @ast.Term::Unit { final_term = recurse(child) }
    }
  }
  (defs, final_term)
}

///|
/// Algebra for CstFold: per-node conversion with framework-managed recursion.
/// Handles both SourceFile (LetDef* Expression?) and single expressions.
pub fn lambda_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> @ast.Term,
) -> @ast.Term {
  match @syntax.SyntaxKind::from_raw(node.kind()) {
    @syntax.SourceFile => {
      let (defs, final_term) = collect_defs_and_body(node, recurse)
      if defs.is_empty() {
        final_term
      } else {
        @ast.Term::Module(defs, final_term)
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
      match v.value() {
        Some(n) => @ast.Term::Int(n)
        None => @ast.Term::Error("invalid integer literal")
      }
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
        // The parser emits operator+operand pairs, so `ops` and trailing
        // operands stay balanced; the Error branch guards malformed or
        // hand-built CSTs, not normal parser output. Check before recursing
        // so we neither re-overwrite Error nor traverse unreachable operands.
        let mut result = recurse(children[0])
        let mut missing = false
        for i = 1; i < children.length(); i = i + 1 {
          if i - 1 >= ops.length() {
            missing = true
            break
          }
          result = @ast.Term::Bop(ops[i - 1], result, recurse(children[i]))
        }
        if missing {
          @ast.Term::Error("missing binary operator")
        } else {
          result
        }
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
    @syntax.BlockExpr => {
      let (defs, final_term) = collect_defs_and_body(node, recurse)
      if defs.is_empty() && final_term == @ast.Term::Unit {
        @ast.Term::Error("empty block")
      } else {
        @ast.Term::Module(defs, final_term)
      }
    }
    @syntax.HoleLiteral => @ast.Term::Hole(0)
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
