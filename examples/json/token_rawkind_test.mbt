// Round-trip tests: verify Token::to_raw() matches SyntaxKind::to_raw()
// for all token kinds that appear in the CST.
//
// See examples/lambda/src/token_rawkind_test.mbt for full rationale.
// Long-term fix: unify Token and SyntaxKind into a single enum (rowan style).

///|
test "Token::to_raw matches SyntaxKind::to_raw for all token kinds" {
  assert_eq(
    @json.Token::LBrace.to_raw(),
    @json.SyntaxKind::LBraceToken.to_raw(),
  )
  assert_eq(
    @json.Token::RBrace.to_raw(),
    @json.SyntaxKind::RBraceToken.to_raw(),
  )
  assert_eq(
    @json.Token::LBracket.to_raw(),
    @json.SyntaxKind::LBracketToken.to_raw(),
  )
  assert_eq(
    @json.Token::RBracket.to_raw(),
    @json.SyntaxKind::RBracketToken.to_raw(),
  )
  assert_eq(@json.Token::Colon.to_raw(), @json.SyntaxKind::ColonToken.to_raw())
  assert_eq(@json.Token::Comma.to_raw(), @json.SyntaxKind::CommaToken.to_raw())
  assert_eq(
    @json.Token::StringLit.to_raw(),
    @json.SyntaxKind::StringToken.to_raw(),
  )
  assert_eq(
    @json.Token::NumberLit.to_raw(),
    @json.SyntaxKind::NumberToken.to_raw(),
  )
  assert_eq(@json.Token::True.to_raw(), @json.SyntaxKind::TrueKeyword.to_raw())
  assert_eq(
    @json.Token::False.to_raw(),
    @json.SyntaxKind::FalseKeyword.to_raw(),
  )
  assert_eq(@json.Token::Null.to_raw(), @json.SyntaxKind::NullKeyword.to_raw())
  assert_eq(
    @json.Token::Whitespace.to_raw(),
    @json.SyntaxKind::WhitespaceToken.to_raw(),
  )
  assert_eq(
    @json.Token::Error("").to_raw(),
    @json.SyntaxKind::ErrorToken.to_raw(),
  )
  assert_eq(@json.Token::EOF.to_raw(), @json.SyntaxKind::EofToken.to_raw())
}
