// Public API for JSON parsing.

///|
pub suberror ParseError {
  ParseError(String, Token)
}

///|
/// Parse a JSON string, raising on any error.
pub fn parse(input : String) -> JsonValue raise {
  let (value, diags) = parse_json(input) catch {
    @core.LexError(msg) => raise ParseError(msg, EOF)
  }
  if diags.length() > 0 {
    raise ParseError(@core.format_diagnostic(diags[0]), diags[0].got_token)
  }
  value
}

///|
/// Parse a JSON string, returning the value and any diagnostics.
pub fn parse_json(
  source : String,
) -> (JsonValue, Array[@core.Diagnostic[Token]]) raise @core.LexError {
  let (cst, diags) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  (syntax_node_to_json(syntax), diags)
}
