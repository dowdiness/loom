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
/// recovered error nodes are surfaced via `parse_cst_recover` diagnostics.
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
    @syntax.IntLiteral => {
      let v = IntLiteralView::{ node }
      @ast.Term::Int(v.value().unwrap_or(0))
    }
    @syntax.VarRef => {
      let v = VarRefView::{ node }
      @ast.Term::Var(v.name())
    }
    @syntax.LambdaExpr => {
      let v = LambdaExprView::{ node }
      let body = match v.body() {
        Some(b) => view_to_term(b)
        None => @ast.Term::Var("<error>")
      }
      @ast.Term::Lam(v.param(), body)
    }
    @syntax.AppExpr => {
      let v = AppExprView::{ node }
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
    }
    @syntax.BinaryExpr => {
      // Single pass: collect ops (from tokens) and operands (from nodes)
      // together rather than calling ops() + operands() as two traversals.
      let ops : Array[@ast.Bop] = []
      let children : Array[@seam.SyntaxNode] = []
      for elem in node.all_children() {
        match elem {
          @seam.SyntaxElement::Token(t) =>
            if t.kind() == @syntax.PlusToken.to_raw() {
              ops.push(@ast.Bop::Plus)
            } else if t.kind() == @syntax.MinusToken.to_raw() {
              ops.push(@ast.Bop::Minus)
            }
          @seam.SyntaxElement::Node(child) => children.push(child)
        }
      }
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
    @syntax.IfExpr => {
      let v = IfExprView::{ node }
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
    @syntax.LetExpr => {
      let v = LetExprView::{ node }
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
    @syntax.ParenExpr => {
      let v = ParenExprView::{ node }
      match v.inner() {
        Some(inner) => view_to_term(inner)
        None => @ast.Term::Var("<error>")
      }
    }
    @syntax.ErrorNode => @ast.Term::Var("<error>")
    _ => @ast.Term::Var("<error: " + node.kind().to_string() + ">")
  }
}

///|
/// Convert a SourceFile SyntaxNode (LetDef* Expression?) to a Term.
///
/// Right-folds definitions: [LetDef(x1,e1), LetDef(x2,e2), Expression(e3)]
/// → Let("x1", e1, Let("x2", e2, e3)).
/// No final expression → uses Unit as terminal.
pub fn syntax_node_to_source_file_term(root : @seam.SyntaxNode) -> @ast.Term {
  let defs : Array[(@ast.VarName, @ast.Term)] = []
  let mut final_term : @ast.Term = @ast.Term::Unit
  for child in root.children() {
    match @syntax.SyntaxKind::from_raw(child.kind()) {
      @syntax.LetDef => {
        let name = child
          .find_token(@syntax.IdentToken.to_raw())
          .map(fn(t) { t.text() })
          .unwrap_or("")
        let init = match child.nth_child(0) {
          Some(expr_node) => view_to_term(expr_node)
          None => @ast.Term::Var("<error>")
        }
        defs.push((name, init))
      }
      _ => final_term = view_to_term(child)
    }
  }
  let mut result = final_term
  for i = defs.length() - 1; i >= 0; i = i - 1 {
    let (name, init) = defs[i]
    result = @ast.Term::Let(name, init, result)
  }
  result
}
