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
    let mut brace_depth = 0
    let mut bracket_depth = 0
    for token in tokens {
      match token.token {
        LBrace => brace_depth = brace_depth + 1
        RBrace => brace_depth = brace_depth - 1
        LBracket => bracket_depth = bracket_depth + 1
        RBracket => bracket_depth = bracket_depth - 1
        _ => ()
      }
      if brace_depth < 0 || bracket_depth < 0 {
        return false
      }
    }
    brace_depth == 0 && bracket_depth == 0
  },
}
