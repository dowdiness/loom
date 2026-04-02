// Round-trip tests: verify Token::to_raw() matches SyntaxKind::to_raw()
// for all token kinds that appear in the CST.
//
// Why: Token and SyntaxKind define to_raw() independently with hardcoded
// integers. If someone adds a SyntaxKind variant and shifts numbers without
// updating Token::to_raw(), incremental reuse silently breaks — old tokens
// never match new tokens, parsing falls back to full reparse on every edit.
//
// Long-term fix: unify Token and SyntaxKind into a single enum (rowan style).
// The payload removal (PR #70) made this feasible — Token is now pure tags.
// Until then, these tests catch desynchronization at test time.

///|
test "Token::to_raw matches SyntaxKind::to_raw for all token kinds" {
  // Fixed tokens (keywords, operators, punctuation)
  assert_eq(@token.Token::Lambda.to_raw(), @syntax.LambdaToken.to_raw())
  assert_eq(@token.Token::Dot.to_raw(), @syntax.DotToken.to_raw())
  assert_eq(@token.Token::LeftParen.to_raw(), @syntax.LeftParenToken.to_raw())
  assert_eq(@token.Token::RightParen.to_raw(), @syntax.RightParenToken.to_raw())
  assert_eq(@token.Token::Plus.to_raw(), @syntax.PlusToken.to_raw())
  assert_eq(@token.Token::Minus.to_raw(), @syntax.MinusToken.to_raw())
  assert_eq(@token.Token::If.to_raw(), @syntax.IfKeyword.to_raw())
  assert_eq(@token.Token::Then.to_raw(), @syntax.ThenKeyword.to_raw())
  assert_eq(@token.Token::Else.to_raw(), @syntax.ElseKeyword.to_raw())
  assert_eq(@token.Token::Let.to_raw(), @syntax.LetKeyword.to_raw())
  assert_eq(@token.Token::Eq.to_raw(), @syntax.EqToken.to_raw())
  assert_eq(@token.Token::LBrace.to_raw(), @syntax.LBraceToken.to_raw())
  assert_eq(@token.Token::RBrace.to_raw(), @syntax.RBraceToken.to_raw())
  assert_eq(@token.Token::Comma.to_raw(), @syntax.CommaToken.to_raw())
  assert_eq(@token.Token::Semicolon.to_raw(), @syntax.SemicolonToken.to_raw())
  assert_eq(@token.Token::Hole.to_raw(), @syntax.HoleToken.to_raw())
  // Content tokens (text varies, kind must still match)
  assert_eq(@token.Token::Identifier.to_raw(), @syntax.IdentToken.to_raw())
  assert_eq(@token.Token::Integer.to_raw(), @syntax.IntToken.to_raw())
  // Trivia and structural tokens
  assert_eq(@token.Token::Whitespace.to_raw(), @syntax.WhitespaceToken.to_raw())
  assert_eq(@token.Token::Newline.to_raw(), @syntax.NewlineToken.to_raw())
  assert_eq(@token.Token::Error("").to_raw(), @syntax.ErrorToken.to_raw())
  assert_eq(@token.Token::EOF.to_raw(), @syntax.EofToken.to_raw())
  // Note: Token::In maps to RawKind(24) but has no SyntaxKind variant.
  // `in` is consumed by the parser during let...in parsing and never
  // emitted as a CST leaf, so no SyntaxKind correspondence is needed.
}
