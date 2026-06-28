///|
/// Convert a language-specific syntax kind to its language-agnostic RawKind.
/// Implement this on any syntax-kind type used with LanguageSpec.
pub(open) trait ToRawKind {
  fn to_raw(Self) -> RawKind
}

///|
/// Construct a language-specific syntax kind from a language-agnostic RawKind.
/// Used by seam internals for round-trip conversions (e.g. first_token filtering).
pub(open) trait FromRawKind {
  fn from_raw(RawKind) -> Self
}

///|
/// Classify a token or syntax-kind as trivia (whitespace, comments).
/// Trivia is skipped during non-trivia token queries.
pub(open) trait IsTrivia {
  fn is_trivia(Self) -> Bool
}

///|
/// Classify a token or syntax-kind as an error sentinel.
pub(open) trait IsError {
  fn is_error(Self) -> Bool
}

///|
/// Classify a token as end-of-input.
/// Implement this on the token type T used with LanguageSpec.
pub(open) trait IsEof {
  fn is_eof(Self) -> Bool
}

///|
/// Marker trait for typed SyntaxNode view types.
///
/// Every view type in your language package should implement this trait
/// and also provide a `pub fn ViewType::cast(n : SyntaxNode) -> Self?`
/// static function (can't be in the trait — MoonBit traits require self
/// as first parameter).
///
/// Example:
///   pub struct LambdaExprView { node : SyntaxNode }
///   pub impl AstView for LambdaExprView with syntax_node(self) { self.node }
///   pub fn LambdaExprView::cast(n : SyntaxNode) -> LambdaExprView? { ... }
pub(open) trait AstView {
  /// Return the underlying raw SyntaxNode.
  fn syntax_node(Self) -> SyntaxNode
}
