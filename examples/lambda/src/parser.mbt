// Parser for Lambda Calculus expressions

///|
pub suberror ParseError {
  ParseError(String, @token.Token)
}

///|
fn token_from_raw_kind(raw : @seam.RawKind) -> @token.Token {
  match @syntax.SyntaxKind::from_raw(raw) {
    @syntax.LambdaToken => @token.Lambda
    @syntax.DotToken => @token.Dot
    @syntax.LeftParenToken => @token.LeftParen
    @syntax.RightParenToken => @token.RightParen
    @syntax.PlusToken => @token.Plus
    @syntax.MinusToken => @token.Minus
    @syntax.IfKeyword => @token.If
    @syntax.ThenKeyword => @token.Then
    @syntax.ElseKeyword => @token.Else
    @syntax.IdentToken => @token.Identifier
    @syntax.IntToken => @token.Integer
    @syntax.WhitespaceToken => @token.Whitespace
    @syntax.ErrorToken => @token.Error("")
    @syntax.EofToken => @token.EOF
    @syntax.LetKeyword => @token.Let
    @syntax.EqToken => @token.Eq
    @syntax.NewlineToken => @token.Newline
    @syntax.LBraceToken => @token.LBrace
    @syntax.RBraceToken => @token.RBrace
    @syntax.CommaToken => @token.Comma
    @syntax.SemicolonToken => @token.Semicolon
    @syntax.HoleToken => @token.Hole
    @syntax.ColonToken => @token.Colon
    @syntax.ArrowToken => @token.Arrow
    _ => @token.EOF
  }
}

///|
fn recoverable_tokens(input : String) -> Array[@core.TokenInfo[@token.Token]] {
  @core.TokenBuffer::new_from_steps(
    input,
    @core.PrefixLexer::new(lex_step=@lexer.lambda_step_lexer),
    eof_token=@token.EOF,
    error_token=@token.Error(""),
    error_token_from_message=Some(fn(msg) { @token.Error(msg) }),
  ).get_tokens()
}

///|
fn token_at_offset(input : String, offset : Int) -> @token.Token {
  let tokens = recoverable_tokens(input)
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
  @token.EOF
}

///|
fn token_for_diagnostic(
  input : String,
  diagnostic : @core.Diagnostic,
) -> @token.Token {
  match diagnostic.primary {
    Some(range) => token_at_offset(input, range.start().value())
    None =>
      match diagnostic.token {
        Some(evidence) => token_from_raw_kind(evidence.kind)
        None => @token.EOF
      }
  }
}

///|
/// Parse the input string into a Term (without position information).
pub fn parse(input : String) -> @ast.Term raise {
  let (term, diags) = parse_term(input) catch {
    @core.LexError(msg) => raise ParseError(msg, @token.EOF)
  }
  if diags.length() > 0 {
    let diagnostic = diags.items()[0]
    raise ParseError(diagnostic.format(), token_for_diagnostic(input, diagnostic))
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
) -> (@ast.Term, @core.DiagnosticSet) raise @core.LexError {
  let (cst, diags) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  (syntax_node_to_term(syntax), diags)
}
