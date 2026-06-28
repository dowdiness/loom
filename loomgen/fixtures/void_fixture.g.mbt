///|
pub fn is_void_element(kind : SyntaxKind) -> Bool {
  match kind {
    HoleLiteral => true
    _ => false
  }
}

///|
pub fn is_raw_text_element(kind : SyntaxKind) -> Bool {
  match kind {
    IntLiteral => true
    _ => false
  }
}
