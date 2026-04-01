///|
/// Token-CST matching for incremental reuse.
/// Text and CodeText compare by text content — without this, the incremental
/// parser could reuse a cached CST subtree whose text has changed (e.g., after
/// editing paragraph content). All other tokens compare by kind only; their
/// CST text width already distinguishes different instances.
fn cst_token_matches(raw : @seam.RawKind, text : String, token : Token) -> Bool {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(raw)
  match (kind, token) {
    (TextToken, Text(s)) => text == s
    (CodeTextToken, CodeText(s)) => text == s
    (HeadingMarkerToken, HeadingMarker(_)) => true
    (ListMarkerToken, ListMarker) => true
    (CodeFenceOpenToken, CodeFenceOpen(_, _)) => true
    (CodeFenceCloseToken, CodeFenceClose) => true
    (BlankLineToken, BlankLine) => true
    (StarToken, Star) => true
    (StarStarToken, StarStar) => true
    (BacktickToken, Backtick) => true
    (LeftBracketToken, LeftBracket) => true
    (RightBracketToken, RightBracket) => true
    (LeftParenToken, LeftParen) => true
    (RightParenToken, RightParen) => true
    (NewlineToken, Newline) => true
    (EofToken, EOF) => true
    (ErrorToken, Error(_)) => true
    _ => false
  }
}

///|
pub let markdown_spec : @core.LanguageSpec[Token, SyntaxKind] = @core.LanguageSpec::new(
  ErrorToken, // whitespace_kind — no trivia, placeholder (never used)
  ErrorNode, // error_kind
  DocumentNode, // root_kind
  EOF, // eof_token
  cst_token_matches~,
  parse_root~,
  reuse_size_threshold=0,
)
