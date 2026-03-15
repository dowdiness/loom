// Parser for Lambda Calculus expressions

///|
pub suberror ParseError {
  ParseError(String, @token.Token)
}

///|
/// Parse the input string into a Term (without position information).
pub fn parse(input : String) -> @ast.Term raise {
  let (term, diags) = parse_term(input) catch {
    @core.LexError(msg) => raise ParseError(msg, @token.EOF)
  }
  if diags.length() > 0 {
    raise ParseError(
      @core.format_diagnostic(diags[0]),
      diags[0].got_token,
    )
  }
  term
}

///|
/// Parse a source string (LetDef* Expression?) and convert to Term.
///
/// Definitions are right-folded into nested Let terms with Unit as terminal
/// when no final expression is present.
pub fn parse_term(
  source : String,
) -> (@ast.Term, Array[@core.Diagnostic[@token.Token]]) raise @core.LexError {
  let (cst, diags) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  (syntax_node_to_term(syntax), diags)
}
