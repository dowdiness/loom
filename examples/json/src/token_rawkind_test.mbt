// Round-trip tests: verify Token::to_raw() matches SyntaxKind::to_raw()
// for all token kinds that appear in the CST.
//
// See examples/lambda/src/token_rawkind_test.mbt for full rationale.
// Long-term fix: unify Token and SyntaxKind into a single enum (rowan style).

///|
test "Token::to_raw matches SyntaxKind::to_raw for all token kinds" {
  assert_eq(Token::LBrace.to_raw(), SyntaxKind::LBraceToken.to_raw())
  assert_eq(Token::RBrace.to_raw(), SyntaxKind::RBraceToken.to_raw())
  assert_eq(Token::LBracket.to_raw(), SyntaxKind::LBracketToken.to_raw())
  assert_eq(Token::RBracket.to_raw(), SyntaxKind::RBracketToken.to_raw())
  assert_eq(Token::Colon.to_raw(), SyntaxKind::ColonToken.to_raw())
  assert_eq(Token::Comma.to_raw(), SyntaxKind::CommaToken.to_raw())
  assert_eq(Token::StringLit.to_raw(), SyntaxKind::StringToken.to_raw())
  assert_eq(Token::NumberLit.to_raw(), SyntaxKind::NumberToken.to_raw())
  assert_eq(Token::True.to_raw(), SyntaxKind::TrueKeyword.to_raw())
  assert_eq(Token::False.to_raw(), SyntaxKind::FalseKeyword.to_raw())
  assert_eq(Token::Null.to_raw(), SyntaxKind::NullKeyword.to_raw())
  assert_eq(Token::Whitespace.to_raw(), SyntaxKind::WhitespaceToken.to_raw())
  assert_eq(Token::Error("").to_raw(), SyntaxKind::ErrorToken.to_raw())
  assert_eq(Token::EOF.to_raw(), SyntaxKind::EofToken.to_raw())
}
