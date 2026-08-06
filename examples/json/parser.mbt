// Public API for JSON parsing.

///|
pub suberror ParseError {
  ParseError(String)
}

///|
/// Parse a JSON string, raising on any error.
pub fn parse(source_id : @core.SourceId, input : String) -> JsonValue raise {
  let (value, diags) = parse_json(source_id, input) catch {
    @core.LexError(msg) => raise ParseError(msg)
    error => raise error
  }
  if diags.length() > 0 {
    let diagnostic = diags.items()[0]
    raise ParseError(diagnostic.format())
  }
  match value {
    Error(msg) => raise ParseError(msg)
    _ => value
  }
}

///|
/// Parse a JSON string, returning the value and any diagnostics.
pub fn parse_json(
  source_id : @core.SourceId,
  source : String,
) -> (JsonValue, @core.DiagnosticSet) raise {
  let (cst, diags) = parse_cst(source_id, source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  (syntax_node_to_json(syntax), diags)
}
