///|
fn is_json_container_kind(kind : @seam.RawKind) -> Bool {
  kind == ObjectNode.to_raw() || kind == ArrayNode.to_raw()
}

///|
fn json_container_depth(node : @seam.SyntaxNode) -> Int {
  let mut depth = 0
  let mut current = node.parent()
  while current is Some(parent) {
    if is_json_container_kind(parent.kind()) {
      depth = depth + 1
    }
    current = parent.parent()
  }
  depth
}

///|
/// JSON block reparse specification.
/// Objects and Arrays are reparseable — edits inside them can be reparsed
/// in isolation instead of reparsing the entire document.
pub let json_block_reparse_spec : @core.BlockReparseSpec[Token, SyntaxKind] = {
  is_reparseable: is_json_container_kind,
  get_reparser: fn(node) {
    let kind = node.kind()
    let depth = json_container_depth(node)
    if kind == ObjectNode.to_raw() {
      Some(fn(ctx) { parse_object_at_depth(ctx, depth~) })
    } else if kind == ArrayNode.to_raw() {
      Some(fn(ctx) { parse_array_at_depth(ctx, depth~) })
    } else {
      None
    }
  },
  is_balanced: fn(tokens) {
    let stack : Array[Token] = []
    for token in tokens {
      match token.token {
        LBrace => stack.push(LBrace)
        LBracket => stack.push(LBracket)
        RBrace =>
          match stack.pop() {
            Some(LBrace) => ()
            _ => return false
          }
        RBracket =>
          match stack.pop() {
            Some(LBracket) => ()
            _ => return false
          }
        _ => ()
      }
    }
    stack.is_empty()
  },
}
