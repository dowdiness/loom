///|
/// Find the byte range of the identifier token corresponding to `def`.
/// `Def.start/end` is the wider containing-node range; `name_start/end`
/// is the identifier-only range used for edits.
pub fn name_range_of(
  def : @callers.Def,
  _syntax : @seam.SyntaxNode,
) -> (Int, Int) {
  (def.name_start, def.name_end)
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
