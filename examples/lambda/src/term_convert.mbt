// term_convert.mbt — SyntaxNode → Term conversion via typed views.

///|
/// Convert a SyntaxNode to a Term using typed view types.
/// Replaces the old AstNode-based path: SyntaxNode → AstNode → Term.
/// SourceFile wraps the actual expression in a single child; this function
/// unwraps it automatically.
///
/// **Well-formed parses only.** For error-recovered trees, only the first
/// node child of SourceFile is used; additional error-recovery siblings are
/// silently dropped. `Term` has no Error variant, so partially-recovered
/// expressions cannot be represented in the term tree. Parse errors and
/// recovered error nodes are surfaced via `ReactiveParser::diagnostics()`.
pub fn syntax_node_to_term(root : @seam.SyntaxNode) -> @ast.Term {
  let node = match @syntax.SyntaxKind::from_raw(root.kind()) {
    @syntax.SourceFile =>
      match root.nth_child(0) {
        Some(child) => child
        None => return @ast.Term::Var("<empty>")
      }
    _ => root
  }
  view_to_term(node)
}

///|
fn view_to_term(node : @seam.SyntaxNode) -> @ast.Term {
  match @syntax.SyntaxKind::from_raw(node.kind()) {
    @syntax.IntLiteral =>
      match IntLiteralView::cast(node) {
        Some(v) => @ast.Term::Int(v.value().unwrap_or(0))
        None => @ast.Term::Var("<error>")
      }
    @syntax.VarRef =>
      match VarRefView::cast(node) {
        Some(v) => @ast.Term::Var(v.name())
        None => @ast.Term::Var("<error>")
      }
    @syntax.LambdaExpr =>
      match LambdaExprView::cast(node) {
        Some(v) => {
          let body = match v.body() {
            Some(b) => view_to_term(b)
            None => @ast.Term::Var("<error>")
          }
          @ast.Term::Lam(v.param(), body)
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.AppExpr =>
      match AppExprView::cast(node) {
        Some(v) =>
          match v.func() {
            None => @ast.Term::Var("<error>")
            Some(func_node) => {
              let mut result = view_to_term(func_node)
              for arg in v.args() {
                result = @ast.Term::App(result, view_to_term(arg))
              }
              result
            }
          }
        None => @ast.Term::Var("<error>")
      }
    @syntax.BinaryExpr =>
      match BinaryExprView::cast(node) {
        Some(v) => {
          let ops = v.ops()
          let children = v.operands()
          if children.length() >= 2 {
            let mut result = view_to_term(children[0])
            for i = 1; i < children.length(); i = i + 1 {
              let op = if i - 1 < ops.length() {
                ops[i - 1]
              } else {
                @ast.Bop::Plus
              }
              result = @ast.Term::Bop(op, result, view_to_term(children[i]))
            }
            result
          } else if children.length() == 1 {
            view_to_term(children[0])
          } else {
            @ast.Term::Var("<error>")
          }
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.IfExpr =>
      match IfExprView::cast(node) {
        Some(v) => {
          let cond = match v.condition() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let then_ = match v.then_branch() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let else_ = match v.else_branch() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          @ast.Term::If(cond, then_, else_)
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.LetExpr =>
      match LetExprView::cast(node) {
        Some(v) => {
          let init = match v.init() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let body = match v.body() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          @ast.Term::Let(v.name(), init, body)
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.ParenExpr =>
      match ParenExprView::cast(node) {
        Some(v) =>
          match v.inner() {
            Some(inner) => view_to_term(inner)
            None => @ast.Term::Var("<error>")
          }
        None => @ast.Term::Var("<error>")
      }
    _ => @ast.Term::Var("<error: " + node.kind().to_string() + ">")
  }
}
