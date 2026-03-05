// term_convert.mbt — SyntaxNode → Term conversion via typed views.

///|
/// Convert a SyntaxNode to a Term using typed view types.
/// Replaces the old AstNode-based path: SyntaxNode → AstNode → Term.
/// SourceFile wraps the actual expression in a single child; this function
/// unwraps it automatically.
///
/// For error-recovered trees, only the first node child of SourceFile is used;
/// additional error-recovery siblings are silently dropped. Partially-recovered
/// expressions are represented as `Term::Error(msg)` in the term tree.
///
/// **Contract:** Pass only trees produced by the lambda-grammar entry points
/// (`parse`, `parse_cst`, `parse_cst_recover*`). Trees produced by
/// `parse_source_file` contain `LetDef` nodes that are not handled here — they
/// fall through to `Term::Error("unknown node kind: LetDef")`. Use
/// `syntax_node_to_source_file_term` for source-file grammar trees.
pub fn syntax_node_to_term(root : @seam.SyntaxNode) -> @ast.Term {
  let node = match @syntax.SyntaxKind::from_raw(root.kind()) {
    @syntax.SourceFile =>
      match root.nth_child(0) {
        Some(child) => child
        None => return @ast.Term::Error("empty SourceFile")
      }
    _ => root
  }
  view_to_term(node)
}

///|
fn view_to_term(node : @seam.SyntaxNode) -> @ast.Term {
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
        Some(b) => view_to_term(b)
        None => @ast.Term::Error("missing lambda body")
      }
      @ast.Term::Lam(v.param(), body)
    }
    @syntax.AppExpr => {
      let v = AppExprView::{ node, }
      match v.func() {
        None => @ast.Term::Error("missing function in application")
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
        @ast.Term::Error("empty BinaryExpr")
      }
    }
    @syntax.IfExpr => {
      let v = IfExprView::{ node, }
      let cond = match v.condition() {
        Some(n) => view_to_term(n)
        None => @ast.Term::Error("missing if condition")
      }
      let then_ = match v.then_branch() {
        Some(n) => view_to_term(n)
        None => @ast.Term::Error("missing then branch")
      }
      let else_ = match v.else_branch() {
        Some(n) => view_to_term(n)
        None => @ast.Term::Error("missing else branch")
      }
      @ast.Term::If(cond, then_, else_)
    }
    @syntax.LetExpr => {
      let v = LetExprView::{ node, }
      let init = match v.init() {
        Some(n) => view_to_term(n)
        None => @ast.Term::Error("missing let binding value")
      }
      let body = match v.body() {
        Some(n) => view_to_term(n)
        None => @ast.Term::Error("missing let body")
      }
      @ast.Term::Let(v.name(), init, body)
    }
    @syntax.ParenExpr => {
      let v = ParenExprView::{ node, }
      match v.inner() {
        Some(inner) => view_to_term(inner)
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
/// Convert a SourceFile SyntaxNode (LetDef* Expression?) to a Term.
///
/// Right-folds definitions: [LetDef(x1,e1), LetDef(x2,e2), Expression(e3)]
/// → Let("x1", e1, Let("x2", e2, e3)).
/// No final expression → uses Unit as terminal.
///
/// Malformed LetDef nodes (missing init expression) produce `Term::Error(...)`.
pub fn syntax_node_to_source_file_term(root : @seam.SyntaxNode) -> @ast.Term {
  let defs : Array[(@ast.VarName, @ast.Term)] = []
  let mut final_term : @ast.Term = @ast.Term::Unit
  for child in root.children() {
    match @syntax.SyntaxKind::from_raw(child.kind()) {
      @syntax.LetDef => {
        let v = LetDefView::{ node: child }
        let init = match v.init() {
          Some(expr_node) => view_to_term(expr_node)
          None => @ast.Term::Error("missing LetDef init")
        }
        defs.push((v.name(), init))
      }
      _ => if final_term == @ast.Term::Unit { final_term = view_to_term(child) }
    }
  }
  let mut result = final_term
  for i = defs.length() - 1; i >= 0; i = i - 1 {
    let (name, init) = defs[i]
    result = @ast.Term::Let(name, init, result)
  }
  result
}
