///|
pub let markdown_spec : @core.LanguageSpec[Token, SyntaxKind] = @core.LanguageSpec::new(
  ErrorToken, // whitespace_kind — no trivia, placeholder (never used)
  ErrorNode, // error_kind
  DocumentNode, // root_kind
  EOF, // eof_token
  parse_root~,
  reuse_size_threshold=0,
)
