///|
/// JSON editor-facing syntax roles.
///
/// These roles are intentionally local to the JSON example. They describe CST
/// token roles for highlighting/projection, not JSON domain graph roles.
pub(all) enum JsonRole {
  PropertyKey
  StringValue
  NumberLiteral
  BooleanLiteral
  NullLiteral
  Punctuation
  Error
} derive(Eq, Debug)

///|
/// A role assigned to a UTF-16 source span.
pub struct JsonRoleSpan {
  priv role : JsonRole
  priv start : Int
  priv end : Int
} derive(Eq, Debug)

///|
pub fn JsonRoleSpan::JsonRoleSpan(
  role~ : JsonRole,
  start~ : Int,
  end~ : Int,
) -> JsonRoleSpan {
  { role, start, end }
}

///|
pub fn JsonRoleSpan::role(self : JsonRoleSpan) -> JsonRole {
  self.role
}

///|
pub fn JsonRoleSpan::start(self : JsonRoleSpan) -> Int {
  self.start
}

///|
pub fn JsonRoleSpan::end(self : JsonRoleSpan) -> Int {
  self.end
}

///|
fn json_token_role(
  parent_kind : SyntaxKind,
  token_kind : SyntaxKind,
) -> JsonRole? {
  match (parent_kind, token_kind) {
    (_, WhitespaceToken | EofToken) => None
    (_, ErrorToken) | (ErrorNode, _) => Some(Error)
    (MemberNode, StringToken) => Some(PropertyKey)
    (
      _,
      LBraceToken
      | RBraceToken
      | LBracketToken
      | RBracketToken
      | ColonToken
      | CommaToken,
    ) => Some(Punctuation)
    (_, StringToken) => Some(StringValue)
    (_, NumberToken) => Some(NumberLiteral)
    (_, TrueKeyword | FalseKeyword) => Some(BooleanLiteral)
    (_, NullKeyword) => Some(NullLiteral)
    _ => None
  }
}

///|
fn json_role_spans_iter(node : @seam.SyntaxNode) -> Iter[JsonRoleSpan] {
  let parent_kind = SyntaxKind::from_raw(node.kind())
  node
  .direct_elements_iter()
  .flat_map(element => {
    match element {
      Node(child) => json_role_spans_iter(child)
      Token(token) =>
        match json_token_role(parent_kind, SyntaxKind::from_raw(token.kind())) {
          Some(role) =>
            Iter::singleton(
              JsonRoleSpan(role~, start=token.start(), end=token.end()),
            )
          None => Iter::empty()
        }
    }
  })
}

///|
/// Project a JSON syntax tree to ordered editor role spans.
///
/// Whitespace and EOF are intentionally omitted. String tokens that are direct
/// children of `MemberNode` become `PropertyKey`; string tokens elsewhere become
/// `StringValue`.
pub fn project_json_roles(syntax : @seam.SyntaxNode) -> Array[JsonRoleSpan] {
  json_role_spans_iter(syntax).to_array()
}
