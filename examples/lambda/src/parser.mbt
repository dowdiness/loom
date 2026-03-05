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
