// cst_convert.mbt — CST (SyntaxNode) → Type and TypedTerm conversion.
//
// Two public entry points:
//   type_of_node(n)    — converts a type-position subtree to Type
//   convert_from_cst(n) — converts an expression subtree to TypedTerm,
//                         preserving lambda type annotations that the
//                         Term-based convert() cannot (always emits None).

///|
/// Convert a type-position CST subtree into a `Type`.
/// Returns `TError` for unrecognized kinds or any subtree containing an ErrorNode.
pub fn type_of_node(n : @seam.SyntaxNode) -> Type {
  if has_error_descendant(n) {
    return TError
  }
  match @syntax.SyntaxKind::from_raw(n.kind()) {
    TypeInt => TInt
    TypeUnit => TUnit
    TypeArrow => {
      // TypeArrow has two type children: lhs and rhs.
      let cs = n.children()
      if cs.length() < 2 {
        TError
      } else {
        TArrow(type_of_node(cs[0]), type_of_node(cs[1]))
      }
    }
    _ => TError
  }
}

///|
/// Returns true if `n` or any descendant is an ErrorNode.
fn has_error_descendant(n : @seam.SyntaxNode) -> Bool {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.SyntaxKind::ErrorNode {
    return true
  }
  for c in n.children() {
    if has_error_descendant(c) {
      return true
    }
  }
  false
}

///|
/// Convert a CST SyntaxNode into a TypedTerm.
/// Preserves lambda type annotations (which Term-based convert() cannot).
pub fn convert_from_cst(n : @seam.SyntaxNode) -> TypedTerm {
  match @syntax.SyntaxKind::from_raw(n.kind()) {
    @syntax.SyntaxKind::SourceFile => convert_source_file(n)
    @syntax.SyntaxKind::IntLiteral => {
      let value = match n.find_token(@syntax.SyntaxKind::IntToken.to_raw()) {
        None => 0
        Some(t) => @string.parse_int(t.text()) catch { _ => 0 }
      }
      TypedTerm::Int(value)
    }
    @syntax.SyntaxKind::VarRef =>
      TypedTerm::Var(n.token_text(@syntax.SyntaxKind::IdentToken.to_raw()))
    @syntax.SyntaxKind::HoleLiteral => TypedTerm::Hole(0)
    @syntax.SyntaxKind::ErrorNode => TypedTerm::Error("error node")
    @syntax.SyntaxKind::LambdaExpr => {
      let param = n.token_text(@syntax.SyntaxKind::IdentToken.to_raw())
      let mut annot_node : @seam.SyntaxNode? = None
      let mut body_node : @seam.SyntaxNode? = None
      for c in n.children() {
        let k = @syntax.SyntaxKind::from_raw(c.kind())
        if k == @syntax.SyntaxKind::TypeAnnot {
          if annot_node is None {
            annot_node = Some(c)
          }
        } else if body_node is None {
          body_node = Some(c)
        }
      }
      let annot = match annot_node {
        None => None
        Some(ann) => {
          let cs = ann.children()
          if cs.length() == 0 {
            Some(TError)
          } else {
            Some(type_of_node(cs[0]))
          }
        }
      }
      let body = match body_node {
        Some(b) => convert_from_cst(b)
        None => TypedTerm::Error("missing lambda body")
      }
      TypedTerm::Lam(param, annot, body)
    }
    @syntax.SyntaxKind::AppExpr =>
      match n.nth_child(0) {
        None => TypedTerm::Error("missing function in application")
        Some(func_node) => {
          let mut result = convert_from_cst(func_node)
          for arg in n.children_from(1) {
            result = TypedTerm::App(result, convert_from_cst(arg))
          }
          result
        }
      }
    @syntax.SyntaxKind::BinaryExpr => {
      let (children, all_tokens) = n.nodes_and_tokens()
      let ops : Array[@ast.Bop] = []
      for t in all_tokens {
        if t.kind() == @syntax.PlusToken.to_raw() {
          ops.push(@ast.Bop::Plus)
        } else if t.kind() == @syntax.MinusToken.to_raw() {
          ops.push(@ast.Bop::Minus)
        }
      }
      if children.length() >= 2 {
        let mut result = convert_from_cst(children[0])
        for i = 1; i < children.length(); i = i + 1 {
          let op = if i - 1 < ops.length() {
            ops[i - 1]
          } else {
            @ast.Bop::Plus
          }
          result = TypedTerm::Bop(op, result, convert_from_cst(children[i]))
        }
        result
      } else if children.length() == 1 {
        convert_from_cst(children[0])
      } else {
        TypedTerm::Error("empty BinaryExpr")
      }
    }
    @syntax.SyntaxKind::IfExpr => {
      let cond = match n.nth_child(0) {
        Some(c) => convert_from_cst(c)
        None => TypedTerm::Error("missing if condition")
      }
      let then_ = match n.nth_child(1) {
        Some(c) => convert_from_cst(c)
        None => TypedTerm::Error("missing then branch")
      }
      let else_ = match n.nth_child(2) {
        Some(c) => convert_from_cst(c)
        None => TypedTerm::Error("missing else branch")
      }
      TypedTerm::If(cond, then_, else_)
    }
    @syntax.SyntaxKind::ParenExpr =>
      match n.nth_child(0) {
        Some(inner) => convert_from_cst(inner)
        None => TypedTerm::Error("empty parentheses")
      }
    @syntax.SyntaxKind::BlockExpr => convert_block_expr(n)
    _ => TypedTerm::Error("unhandled CST kind")
  }
}

///|
/// Collect LetDef entries and trailing expression from a node's children.
/// Shared by SourceFile and BlockExpr conversion.
fn collect_typed_defs_and_body(
  node : @seam.SyntaxNode,
) -> (Array[(String, TypedTerm)], TypedTerm) {
  let defs : Array[(String, TypedTerm)] = []
  let mut final_term : TypedTerm = TypedTerm::Unit
  for child in node.children() {
    match @syntax.SyntaxKind::from_raw(child.kind()) {
      @syntax.SyntaxKind::LetDef => {
        let (name, body) = convert_let_def_entry(child)
        defs.push((name, body))
      }
      _ =>
        if final_term == TypedTerm::Unit {
          final_term = convert_from_cst(child)
        }
    }
  }
  (defs, final_term)
}

///|
/// Handle a SourceFile: collect LetDef entries and trailing expression,
/// building a Module when defs are present.
fn convert_source_file(n : @seam.SyntaxNode) -> TypedTerm {
  let (defs, body) = collect_typed_defs_and_body(n)
  if defs.is_empty() {
    body
  } else {
    TypedTerm::Module(defs, body)
  }
}

///|
/// Handle a BlockExpr: same logic as SourceFile — collect defs + trailing expr.
fn convert_block_expr(n : @seam.SyntaxNode) -> TypedTerm {
  let (defs, body) = collect_typed_defs_and_body(n)
  if defs.is_empty() {
    body
  } else {
    TypedTerm::Module(defs, body)
  }
}

///|
/// Convert a LetDef CST node to (name, TypedTerm) pair.
/// Handles both value form (`let a = 1`) and param-list form (`let f(x: Int) = x`).
fn convert_let_def_entry(n : @seam.SyntaxNode) -> (String, TypedTerm) {
  let name = n.token_text(@syntax.SyntaxKind::IdentToken.to_raw())
  let mut param_list : @seam.SyntaxNode? = None
  let mut init : @seam.SyntaxNode? = None
  for c in n.children() {
    let k = @syntax.SyntaxKind::from_raw(c.kind())
    if k == @syntax.SyntaxKind::ParamList {
      param_list = Some(c)
    } else if init is None {
      init = Some(c)
    }
  }
  let init_term = match init {
    Some(e) => convert_from_cst(e)
    None => TypedTerm::Error("missing LetDef init")
  }
  let body = match param_list {
    None => init_term
    Some(pl) => {
      let params = convert_param_list(pl)
      let mut b = init_term
      for i = params.length() - 1; i >= 0; i = i - 1 {
        let (nm, ann) = params[i]
        b = TypedTerm::Lam(nm, ann, b)
      }
      b
    }
  }
  (name, body)
}

///|
/// Walk a ParamList's all_children(), pairing IdentTokens with optionally-following
/// TypeAnnot nodes. Returns [(name, annot?), ...].
fn convert_param_list(pl : @seam.SyntaxNode) -> Array[(String, Type?)] {
  let result : Array[(String, Type?)] = []
  let mut pending_name : String? = None
  let mut pending_annot : Type? = None
  for elem in pl.all_children() {
    match elem {
      @seam.SyntaxElement::Token(t) => {
        let kind = @syntax.SyntaxKind::from_raw(t.kind())
        if kind == @syntax.SyntaxKind::IdentToken {
          // Flush previous pending param if any
          match pending_name {
            Some(nm) => {
              result.push((nm, pending_annot))
              pending_annot = None
            }
            None => ()
          }
          pending_name = Some(t.text())
        } else if kind == @syntax.SyntaxKind::CommaToken ||
          kind == @syntax.SyntaxKind::RightParenToken {
          // Flush on comma or closing paren
          match pending_name {
            Some(nm) => {
              result.push((nm, pending_annot))
              pending_name = None
              pending_annot = None
            }
            None => ()
          }
        }
      }
      @seam.SyntaxElement::Node(node) => {
        let kind = @syntax.SyntaxKind::from_raw(node.kind())
        if kind == @syntax.SyntaxKind::TypeAnnot {
          let cs = node.children()
          pending_annot = if cs.length() == 0 {
            Some(TError)
          } else {
            Some(type_of_node(cs[0]))
          }
        }
      }
    }
  }
  // Flush any remaining pending param
  match pending_name {
    Some(nm) => result.push((nm, pending_annot))
    None => ()
  }
  result
}
