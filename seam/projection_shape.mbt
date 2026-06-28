///|
/// Kind of direct child element being validated by projection shape helpers.
pub(all) enum ProjectionShapeElement {
  TokenElement
  ChildElement
} derive(Debug, Eq)

///|
/// Cardinality expected by a projection shape helper.
pub(all) enum ProjectionShapeExpectation {
  ExpectedZero
  ExpectedOptional
  ExpectedOne
  ExpectedAtLeastOne
} derive(Debug, Eq)

///|
/// Structured error returned by projection shape helpers.
///
/// `message` is supplied by the projection author so language-specific error
/// text stays at the projection layer. `start` and `end` identify the source
/// range to underline: the matched direct elements when present, or the node's
/// whole range when the expected element is missing.
pub(all) struct ProjectionShapeError {
  message : String
  node_kind : RawKind
  target_kind : RawKind
  element : ProjectionShapeElement
  expectation : ProjectionShapeExpectation
  actual : Int
  start : Int
  end : Int
} derive(Debug, Eq)

///|
pub fn ProjectionShapeError::ProjectionShapeError(
  node : SyntaxNode,
  target_kind : RawKind,
  element : ProjectionShapeElement,
  expectation : ProjectionShapeExpectation,
  actual : Int,
  start : Int,
  end : Int,
  message~ : String,
) -> ProjectionShapeError {
  {
    message,
    node_kind: node.kind(),
    target_kind,
    element,
    expectation,
    actual,
    start,
    end,
  }
}

///|
fn token_match_range(
  node : SyntaxNode,
  matches : Array[SyntaxToken],
) -> (Int, Int) {
  if matches.length() == 0 {
    (node.start(), node.end())
  } else {
    (matches[0].start(), matches[matches.length() - 1].end())
  }
}

///|
fn child_match_range(
  node : SyntaxNode,
  matches : Array[SyntaxNode],
) -> (Int, Int) {
  if matches.length() == 0 {
    (node.start(), node.end())
  } else {
    (matches[0].start(), matches[matches.length() - 1].end())
  }
}

///|
fn token_shape_error(
  node : SyntaxNode,
  kind : RawKind,
  matches : Array[SyntaxToken],
  expectation : ProjectionShapeExpectation,
  message~ : String,
) -> ProjectionShapeError {
  let (start, end) = token_match_range(node, matches)
  ProjectionShapeError(
    node,
    kind,
    TokenElement,
    expectation,
    matches.length(),
    start,
    end,
    message~,
  )
}

///|
fn child_shape_error(
  node : SyntaxNode,
  kind : RawKind,
  matches : Array[SyntaxNode],
  expectation : ProjectionShapeExpectation,
  message~ : String,
) -> ProjectionShapeError {
  let (start, end) = child_match_range(node, matches)
  ProjectionShapeError(
    node,
    kind,
    ChildElement,
    expectation,
    matches.length(),
    start,
    end,
    message~,
  )
}

///|
/// First direct child node matching `kind`, or `None` when no direct child of
/// that kind exists.
///
/// Alias with an explicit name for projection code that validates concrete
/// argument shape. Equivalent to `child_of_kind(kind)`.
pub fn SyntaxNode::direct_child_of_kind(
  self : SyntaxNode,
  kind : RawKind,
) -> SyntaxNode? {
  self.child_of_kind(kind)
}

///|
/// Require zero direct tokens of `kind`.
///
/// Returns `Err` with the projection-supplied message and the matching token
/// span when one or more tokens are present.
pub fn SyntaxNode::expect_no_direct_tokens_of_kind(
  self : SyntaxNode,
  kind : RawKind,
  message~ : String,
) -> Result[Unit, ProjectionShapeError] {
  let matches = self.direct_tokens_of_kind(kind)
  if matches.length() == 0 {
    Ok(())
  } else {
    Err(token_shape_error(self, kind, matches, ExpectedZero, message~))
  }
}

///|
/// Accept zero or one direct token of `kind`; reject two or more.
pub fn SyntaxNode::optional_direct_token_of_kind(
  self : SyntaxNode,
  kind : RawKind,
  message~ : String,
) -> Result[SyntaxToken?, ProjectionShapeError] {
  let matches = self.direct_tokens_of_kind(kind)
  match matches.length() {
    0 => Ok(None)
    1 => Ok(Some(matches[0]))
    _ => Err(token_shape_error(self, kind, matches, ExpectedOptional, message~))
  }
}

///|
/// Require exactly one direct token of `kind`.
pub fn SyntaxNode::required_direct_token_of_kind(
  self : SyntaxNode,
  kind : RawKind,
  message~ : String,
) -> Result[SyntaxToken, ProjectionShapeError] {
  let matches = self.direct_tokens_of_kind(kind)
  match matches.length() {
    1 => Ok(matches[0])
    _ => Err(token_shape_error(self, kind, matches, ExpectedOne, message~))
  }
}

///|
/// Require at least one direct token of `kind`, preserving source order.
pub fn SyntaxNode::required_direct_tokens_of_kind(
  self : SyntaxNode,
  kind : RawKind,
  message~ : String,
) -> Result[Array[SyntaxToken], ProjectionShapeError] {
  let matches = self.direct_tokens_of_kind(kind)
  if matches.length() > 0 {
    Ok(matches)
  } else {
    Err(token_shape_error(self, kind, matches, ExpectedAtLeastOne, message~))
  }
}

///|
/// Accept zero or one direct token of `kind`, returning only token text.
///
/// Reuses `optional_direct_token_of_kind`, so malformed cardinality returns the
/// same `ProjectionShapeError` callers would get from the lower-level helper.
pub fn SyntaxNode::optional_direct_token_text_of_kind(
  self : SyntaxNode,
  kind : RawKind,
  message~ : String,
) -> Result[String?, ProjectionShapeError] {
  match self.optional_direct_token_of_kind(kind, message~) {
    Ok(Some(token)) => Ok(Some(token.text()))
    Ok(None) => Ok(None)
    Err(err) => Err(err)
  }
}

///|
/// Require exactly one direct token of `kind`, returning only token text.
///
/// Reuses `required_direct_token_of_kind`, preserving its cardinality errors.
pub fn SyntaxNode::required_direct_token_text_of_kind(
  self : SyntaxNode,
  kind : RawKind,
  message~ : String,
) -> Result[String, ProjectionShapeError] {
  match self.required_direct_token_of_kind(kind, message~) {
    Ok(token) => Ok(token.text())
    Err(err) => Err(err)
  }
}

///|
/// Require at least one direct token of `kind`, returning token text in source
/// order.
///
/// Reuses `required_direct_tokens_of_kind`, preserving its cardinality errors.
pub fn SyntaxNode::required_direct_tokens_text_of_kind(
  self : SyntaxNode,
  kind : RawKind,
  message~ : String,
) -> Result[Array[String], ProjectionShapeError] {
  match self.required_direct_tokens_of_kind(kind, message~) {
    Ok(tokens) => Ok(tokens.map(token => token.text()))
    Err(err) => Err(err)
  }
}

///|
/// Require zero direct child nodes of `kind`.
pub fn SyntaxNode::expect_no_direct_children_of_kind(
  self : SyntaxNode,
  kind : RawKind,
  message~ : String,
) -> Result[Unit, ProjectionShapeError] {
  let matches = self.direct_children_of_kind(kind)
  if matches.length() == 0 {
    Ok(())
  } else {
    Err(child_shape_error(self, kind, matches, ExpectedZero, message~))
  }
}

///|
/// Accept zero or one direct child node of `kind`; reject two or more.
pub fn SyntaxNode::optional_direct_child_of_kind(
  self : SyntaxNode,
  kind : RawKind,
  message~ : String,
) -> Result[SyntaxNode?, ProjectionShapeError] {
  let matches = self.direct_children_of_kind(kind)
  match matches.length() {
    0 => Ok(None)
    1 => Ok(Some(matches[0]))
    _ => Err(child_shape_error(self, kind, matches, ExpectedOptional, message~))
  }
}

///|
/// Require exactly one direct child node of `kind`.
pub fn SyntaxNode::required_direct_child_of_kind(
  self : SyntaxNode,
  kind : RawKind,
  message~ : String,
) -> Result[SyntaxNode, ProjectionShapeError] {
  let matches = self.direct_children_of_kind(kind)
  match matches.length() {
    1 => Ok(matches[0])
    _ => Err(child_shape_error(self, kind, matches, ExpectedOne, message~))
  }
}

///|
/// Require at least one direct child node of `kind`, preserving source order.
pub fn SyntaxNode::required_direct_children_of_kind(
  self : SyntaxNode,
  kind : RawKind,
  message~ : String,
) -> Result[Array[SyntaxNode], ProjectionShapeError] {
  let matches = self.direct_children_of_kind(kind)
  if matches.length() > 0 {
    Ok(matches)
  } else {
    Err(child_shape_error(self, kind, matches, ExpectedAtLeastOne, message~))
  }
}
