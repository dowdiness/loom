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
  let body = v
    .params()
    .rev_fold(init~, (body, param) => @ast.Term::Lam(param, body))
  (v.name(), body)
}

///|
/// Collect LetDef children and trailing expression from a node.
/// Used by both SourceFile and BlockExpr conversion.
fn collect_defs_and_body(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> @ast.Term,
) -> (Array[(@ast.VarName, @ast.Term)], @ast.Term) {
  let children = node.children()
  let defs = children
    .iter()
    .filter_map(child => {
      match @syntax.SyntaxKind::from_raw(child.kind()) {
        @syntax.LetDef =>
          Some(convert_let_def(LetDefView::{ node: child }, recurse))
        _ => None
      }
    })
    .to_array()
  let final_term = children
    .iter()
    .find_first(child => {
      @syntax.SyntaxKind::from_raw(child.kind()) != @syntax.LetDef
    })
    .map_or(@ast.Term::Unit, recurse)
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
      let body = v
        .body()
        .map_or(@ast.Term::Error("missing lambda body"), recurse)
      @ast.Term::Lam(v.param(), body)
    }
    @syntax.AppExpr => {
      let v = AppExprView::{ node, }
      match v.func() {
        None => @ast.Term::Error("missing function in application")
        Some(func_node) =>
          v
          .args()
          .fold(init=recurse(func_node), (result, arg) => {
            @ast.Term::App(result, recurse(arg))
          })
      }
    }
    @syntax.BinaryExpr => {
      let (children, all_tokens) = node.nodes_and_tokens()
      let ops = all_tokens
        .iter()
        .filter_map(t => {
          if t.kind() == @syntax.PlusToken.to_raw() {
            Some(@ast.Bop::Plus)
          } else if t.kind() == @syntax.MinusToken.to_raw() {
            Some(@ast.Bop::Minus)
          } else {
            None
          }
        })
        .to_array()
      match children {
        [first, _, ..] => {
          // Recovery or hand-built CSTs can leave operator and operand counts
          // unbalanced in either direction. Fold only after exact balance is
          // confirmed so we neither synthesize nor silently drop operators.
          let expected_ops = children.length() - 1
          if ops.length() < expected_ops {
            @ast.Term::Error("missing binary operator")
          } else if ops.length() > expected_ops {
            @ast.Term::Error("excess binary operator(s)")
          } else {
            children
            .iter()
            .drop(1)
            .zip(ops.iter())
            .fold(init=recurse(first), (result, pair) => {
              @ast.Term::Bop(pair.1, result, recurse(pair.0))
            })
          }
        }
        [only] => recurse(only)
        [] => @ast.Term::Error("empty BinaryExpr")
      }
    }
    @syntax.IfExpr => {
      let v = IfExprView::{ node, }
      let cond = v
        .condition()
        .map_or(@ast.Term::Error("missing if condition"), recurse)
      let then_ = v
        .then_branch()
        .map_or(@ast.Term::Error("missing then branch"), recurse)
      let else_ = v
        .else_branch()
        .map_or(@ast.Term::Error("missing else branch"), recurse)
      @ast.Term::If(cond, then_, else_)
    }
    @syntax.ParenExpr => {
      let v = ParenExprView::{ node, }
      v.inner().map_or(@ast.Term::Error("empty parentheses"), recurse)
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
