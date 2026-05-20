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
fn find_ident_in(node : @seam.SyntaxNode, def : @callers.Def) -> (Int, Int)? {
  if node.end() <= def.start || node.start() >= def.end {
    return None
  }
  for child in node.all_children() {
    match child {
      @seam.SyntaxElement::Token(tok) =>
        if @syntax.SyntaxKind::from_raw(tok.kind()) == @syntax.IdentToken &&
          tok.text() == def.name &&
          tok.start() >= def.start &&
          tok.end() <= def.end {
          return Some((tok.start(), tok.end()))
        }
      @seam.SyntaxElement::Node(child_node) =>
        match find_ident_in(child_node, def) {
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
