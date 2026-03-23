// JSON language specification for the generic parser infrastructure.

///|
/// Map RawKind to the corresponding Token for fixed (non-payload) tokens.
fn syntax_kind_to_token_kind(kind : @seam.RawKind) -> Token? {
  match SyntaxKind::from_raw(kind) {
    LBraceToken => Some(LBrace)
    RBraceToken => Some(RBrace)
    LBracketToken => Some(LBracket)
    RBracketToken => Some(RBracket)
    ColonToken => Some(Colon)
    CommaToken => Some(Comma)
    TrueKeyword => Some(True)
    FalseKeyword => Some(False)
    NullKeyword => Some(Null)
    _ => None
  }
}

///|
/// Shared structural token matcher for the JSON spec.
let cst_token_matches : (@seam.RawKind, String, Token) -> Bool = fn(
  raw,
  text,
  tok,
) {
  match SyntaxKind::from_raw(raw) {
    // Payload tokens: compare by text content
    StringToken =>
      match tok {
        StringLit(s) => s == text
        _ => false
      }
    NumberToken =>
      match tok {
        NumberLit(n) => n == text
        _ => false
      }
    // Fixed tokens: compare by kind
    _ =>
      match syntax_kind_to_token_kind(raw) {
        Some(expected) => expected == tok
        None => false
      }
  }
}

///|
/// LanguageSpec for JSON grammar.
/// reuse_size_threshold=0: all nodes eligible for reuse. MemberNode uses ctx.node()
/// so individual object members can be reused during incremental parsing.
let json_spec : @core.LanguageSpec[Token, SyntaxKind] = @core.LanguageSpec::new(
  WhitespaceToken,
  ErrorToken,
  RootNode,
  EOF,
  cst_token_matches~,
  parse_root=parse_json_root,
  reuse_size_threshold=0,
)
