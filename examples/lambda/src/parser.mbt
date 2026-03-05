// Parser for Lambda Calculus expressions

///|
pub suberror ParseError {
  ParseError(String, @token.Token)
}

///|
/// Parse the input string into a Term (without position information).
pub fn parse(input : String) -> @ast.Term raise {
  let cst = parse_cst(input)
  let syn = @seam.SyntaxNode::from_cst(cst)
  syntax_node_to_term(syn)
}

///|
/// Parse a source file (LetDef* Expression?) and convert to Term.
///
/// Definitions are right-folded into nested Let terms with Unit as terminal
/// when no final expression is present.
pub fn parse_source_file_term(
  source : String,
) -> (@ast.Term, Array[@core.Diagnostic[@token.Token]]) raise @core.LexError {
  let (cst, diags) = parse_source_file(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  (syntax_node_to_source_file_term(syntax), diags)
}
