///|
/// JSON block reparse specification.
/// Objects and Arrays are reparseable — edits inside them can be reparsed
/// in isolation instead of reparsing the entire document.
pub let json_block_reparse_spec : @core.BlockReparseSpec[Token, SyntaxKind] = {
  is_reparseable: fn(kind) {
    kind == ObjectNode.to_raw() || kind == ArrayNode.to_raw()
  },
  get_reparser: fn(kind) {
    if kind == ObjectNode.to_raw() {
      Some(parse_object)
    } else if kind == ArrayNode.to_raw() {
      Some(parse_array)
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
