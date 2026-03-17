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
      let defs : Array[(@ast.VarName, @ast.Term)] = []
      let mut final_term : @ast.Term = @ast.Term::Unit
      for child in node.children() {
        match @syntax.SyntaxKind::from_raw(child.kind()) {
          @syntax.LetDef => {
            let v = LetDefView::{ node: child }
            let init = match v.init() {
              Some(expr_node) => recurse(expr_node)
              None => @ast.Term::Error("missing LetDef init")
            }
            defs.push((v.name(), init))
          }
          _ =>
            if final_term == @ast.Term::Unit {
              final_term = recurse(child)
            }
        }
      }
      let mut result = final_term
      for i = defs.length() - 1; i >= 0; i = i - 1 {
        let (name, init) = defs[i]
        result = @ast.Term::Let(name, init, result)
      }
      result
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
/// Convert a SyntaxNode to a Term using typed view types.
///
/// Handles both single-expression trees and source-file grammar trees
/// (LetDef* Expression?).
///
/// Right-folds definitions: [LetDef(x1,e1), LetDef(x2,e2), Expression(e3)]
/// → Let("x1", e1, Let("x2", e2, e3)).
/// No final expression → uses Unit as terminal.
///
/// Malformed LetDef nodes (missing init expression) produce `Term::Error(...)`.
pub fn syntax_node_to_term(root : @seam.SyntaxNode) -> @ast.Term {
  // Non-SourceFile roots (e.g. IntLiteral, LambdaExpr) are converted directly.
  if @syntax.SyntaxKind::from_raw(root.kind()) != @syntax.SourceFile {
    return view_to_term(root)
  }
  // SourceFile: right-fold LetDef* into nested Let terms.
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
