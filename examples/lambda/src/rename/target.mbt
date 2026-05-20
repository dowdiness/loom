///|
/// Find the byte range of the identifier token corresponding to `def`
/// in the syntax tree. `Def.start/end` is the wider containing-node
/// range, so rename needs this helper for identifier-only edits.
pub fn name_range_of(
  def : @callers.Def,
  syntax : @seam.SyntaxNode,
) -> (Int, Int) {
  match find_ident_in(syntax, def) {
    Some(range) => range
    None =>
      abort(
        "name_range_of: no IdentToken matched def \\{def.name} in \\{def.start}..\\{def.end}",
      )
  }
}

///|
/// Find the byte range of the identifier token corresponding to `call`.
/// `Call.start/end` is the wider `VarRef` node range, so rename uses this
/// helper for identifier-only reference edits and labels.
fn call_name_range_of(
  call : @callers.Call,
  syntax : @seam.SyntaxNode,
) -> (Int, Int) {
  match find_call_ident_in(syntax, call) {
    Some(range) => range
    None =>
      abort(
        "call_name_range_of: no IdentToken matched call \\{call.callee} in \\{call.start}..\\{call.end}",
      )
  }
}

///|
fn find_ident_in(node : @seam.SyntaxNode, def : @callers.Def) -> (Int, Int)? {
  if node.end() <= def.start || node.start() >= def.end {
    return None
  }
  if node.start() == def.start && node.end() == def.end {
    match @syntax.SyntaxKind::from_raw(node.kind()) {
      @syntax.LetDef => return find_let_def_ident(node, def)
      @syntax.LambdaExpr => return find_lambda_param_ident(node, def)
      _ => ()
    }
  }
  for child in node.children() {
    match find_ident_in(child, def) {
      Some(range) => return Some(range)
      None => ()
    }
  }
  None
}

///|
fn find_call_ident_in(
  node : @seam.SyntaxNode,
  call : @callers.Call,
) -> (Int, Int)? {
  if node.end() <= call.start || node.start() >= call.end {
    return None
  }
  for child in node.all_children() {
    match child {
      @seam.SyntaxElement::Token(tok) =>
        if @syntax.SyntaxKind::from_raw(tok.kind()) == @syntax.IdentToken &&
          tok.text() == call.callee &&
          tok.start() >= call.start &&
          tok.end() <= call.end {
          return Some((tok.start(), tok.end()))
        }
      @seam.SyntaxElement::Node(child_node) =>
        match find_call_ident_in(child_node, call) {
          Some(range) => return Some(range)
          None => ()
        }
    }
  }
  None
}

///|
fn find_let_def_ident(
  node : @seam.SyntaxNode,
  def : @callers.Def,
) -> (Int, Int)? {
  if is_scope_for_node(def.scope, node) {
    find_param_ident_in_let_def(node, def.name)
  } else {
    match ident_after_lead(node, @syntax.LetKeyword) {
      Some(tok) =>
        if tok.text() == def.name {
          Some((tok.start(), tok.end()))
        } else {
          None
        }
      None => None
    }
  }
}

///|
fn find_lambda_param_ident(
  node : @seam.SyntaxNode,
  def : @callers.Def,
) -> (Int, Int)? {
  if !is_scope_for_node(def.scope, node) {
    return None
  }
  match ident_after_lead(node, @syntax.LambdaToken) {
    Some(tok) =>
      if tok.text() == def.name {
        Some((tok.start(), tok.end()))
      } else {
        None
      }
    None => None
  }
}

///|
fn find_param_ident_in_let_def(
  node : @seam.SyntaxNode,
  name : String,
) -> (Int, Int)? {
  for child in node.children() {
    if @syntax.SyntaxKind::from_raw(child.kind()) == @syntax.ParamList {
      for tok in child.tokens() {
        if @syntax.SyntaxKind::from_raw(tok.kind()) == @syntax.IdentToken &&
          tok.text() == name {
          return Some((tok.start(), tok.end()))
        }
      }
    }
  }
  None
}

///|
fn is_scope_for_node(scope : @callers.ScopeId, node : @seam.SyntaxNode) -> Bool {
  match scope {
    @callers.LambdaScope(start, end) =>
      start == node.start() && end == node.end()
    @callers.TopScope => false
  }
}

///|
fn ident_after_lead(
  node : @seam.SyntaxNode,
  lead_kind : @syntax.SyntaxKind,
) -> @seam.SyntaxToken? {
  let mut seen_lead = false
  for elem in node.all_children() {
    match elem {
      @seam.SyntaxElement::Token(tok) => {
        let k = @syntax.SyntaxKind::from_raw(tok.kind())
        if k.is_trivia() {
          continue
        }
        if seen_lead {
          if k == @syntax.IdentToken {
            return Some(tok)
          }
          return None
        }
        if k == lead_kind {
          seen_lead = true
        }
      }
      @seam.SyntaxElement::Node(_) => if seen_lead { return None }
    }
  }
  None
}

///|
/// Find the def whose identifier range contains `offset`. Returns None
/// for offsets on whitespace, keywords, or expression occurrences.
pub fn locate_target(
  defs : Array[@callers.Def],
  syntax : @seam.SyntaxNode,
  offset : Int,
) -> @callers.Def? {
  for d in defs {
    let (name_start, name_end) = name_range_of(d, syntax)
    if offset >= name_start && offset < name_end {
      return Some(d)
    }
  }
  None
}
