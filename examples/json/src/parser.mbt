// Public API for JSON parsing.

///|
pub suberror ParseError {
  ParseError(String, Token)
}

///|
fn token_from_raw_kind(raw : @seam.RawKind) -> Token {
  match SyntaxKind::from_raw(raw) {
    LBraceToken => LBrace
    RBraceToken => RBrace
    LBracketToken => LBracket
    RBracketToken => RBracket
    ColonToken => Colon
    CommaToken => Comma
    StringToken => StringLit
    NumberToken => NumberLit
    TrueKeyword => True
    FalseKeyword => False
    NullKeyword => Null
    WhitespaceToken => Whitespace
    ErrorToken => Error("")
    EofToken => EOF
    _ => EOF
  }
}

///|
fn token_at_offset(input : String, offset : Int) -> Token {
  let tokens = tokenize_recoverable(input)
  let starts = @core.build_starts(tokens)
  for i = 0; i < tokens.length(); i = i + 1 {
    let start = starts[i]
    let end = start + tokens[i].len
    if start <= offset && (offset < end || tokens[i].len == 0) {
      return tokens[i].token
    }
    if start >= offset {
      return tokens[i].token
    }
  }
  EOF
}

///|
fn token_for_diagnostic(input : String, diagnostic : @core.Diagnostic) -> Token {
  match diagnostic.primary {
    Some(range) => token_at_offset(input, range.start().value())
    None =>
      match diagnostic.token {
        Some(evidence) => token_from_raw_kind(evidence.kind)
        None => EOF
      }
  }
}

///|
/// Parse a JSON string, raising on any error.
pub fn parse(input : String) -> JsonValue raise {
  let (value, diags) = parse_json(input) catch {
    @core.LexError(msg) => raise ParseError(msg, EOF)
  }
  if diags.length() > 0 {
    let diagnostic = diags.items()[0]
    raise ParseError(diagnostic.format(), token_for_diagnostic(input, diagnostic))
  }
  match value {
    Error(msg) => raise ParseError(msg, EOF)
    _ => value
  }
}

///|
/// Parse a JSON string, returning the value and any diagnostics.
pub fn parse_json(
  source : String,
) -> (JsonValue, @core.DiagnosticSet) raise @core.LexError {
  let (cst, diags) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  (syntax_node_to_json(syntax), diags)
}
