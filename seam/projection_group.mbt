///|
/// One element slot produced by `SyntaxNode::direct_element_groups_by`: the
/// direct elements between two adjacent separator tokens, plus the slot's
/// source span recorded while the separators were still visible.
///
/// `start`/`end` cover the matched elements when the group is non-empty. For
/// an empty group they cover the slot itself: parent start to first separator
/// (leading), previous separator end to next separator start (doubled
/// separator), or previous separator end to parent end (trailing) — positions
/// the raw `Array[Array[SyntaxElement]]` groups cannot reconstruct after the
/// walk discards the separators.
pub struct DirectElementGroup {
  priv parent : SyntaxNode
  priv index : Int
  priv elements : Array[SyntaxElement]
  priv start : Int
  priv end : Int
}

///|
/// Build one group from the walk state: non-empty groups span their element
/// extent, empty groups span the slot between the surrounding boundaries.
fn DirectElementGroup::DirectElementGroup(
  parent : SyntaxNode,
  index : Int,
  elements : Array[SyntaxElement],
  slot_start : Int,
  slot_end : Int,
) -> DirectElementGroup {
  let (start, end) = if elements.length() == 0 {
    (slot_start, slot_end)
  } else {
    (elements[0].start(), elements[elements.length() - 1].end())
  }
  { parent, index, elements, start, end }
}

///|
/// Zero-based position of this group among the N+1 slots of its parent walk.
pub fn DirectElementGroup::index(self : DirectElementGroup) -> Int {
  self.index
}

///|
/// Elements of this group in source order (never separator or trivia tokens),
/// as a read-only view: the wrapper's job is to keep `elements` consistent
/// with the slot span computed at construction, so the backing array is not
/// exposed for mutation. Use `direct_elements_grouped_by` when raw arrays are
/// needed.
pub fn DirectElementGroup::elements(
  self : DirectElementGroup,
) -> ArrayView[SyntaxElement] {
  self.elements[:]
}

///|
/// Absolute start of the group span (element extent, or slot span when empty).
pub fn DirectElementGroup::start(self : DirectElementGroup) -> Int {
  self.start
}

///|
/// Absolute end of the group span (element extent, or slot span when empty).
pub fn DirectElementGroup::end(self : DirectElementGroup) -> Int {
  self.end
}

///|
/// True when this slot holds no elements (leading, trailing, or doubled
/// separator).
pub fn DirectElementGroup::is_empty(self : DirectElementGroup) -> Bool {
  self.elements.length() == 0
}

///|
/// Split direct children into span-carrying element groups delimited by
/// `separator` tokens.
///
/// Grouping semantics match `direct_elements_grouped_by` exactly (N
/// separators yield N+1 groups, empty groups are preserved, `trivia_kind`
/// tokens are excluded, `RepeatGroup` nodes are transparent), but each group
/// also records its slot span, computed during the separator walk so that
/// empty slots stay diagnosable. Use the raw API when only the element
/// arrays are needed.
pub fn SyntaxNode::direct_element_groups_by(
  self : SyntaxNode,
  separator : RawKind,
  trivia_kind? : RawKind? = None,
) -> Array[DirectElementGroup] {
  // Builder state: a group closes at each separator token, whose span is the
  // only place the enclosing slot boundaries are visible.
  let groups : Array[DirectElementGroup] = []
  let mut elements : Array[SyntaxElement] = []
  let mut slot_start = self.start()
  for elem in self.direct_elements_iter() {
    match element_to_group_op(elem, separator, trivia_kind) {
      Some(StartGroup(sep)) => {
        groups.push(
          DirectElementGroup(
            self,
            groups.length(),
            elements,
            slot_start,
            sep.start(),
          ),
        )
        elements = []
        slot_start = sep.end()
      }
      Some(AppendElement(elem)) => elements.push(elem)
      None => ()
    }
  }
  groups.push(
    DirectElementGroup(self, groups.length(), elements, slot_start, self.end()),
  )
  groups
}

///|
/// Tokens of this group matching `kind`, in source order.
fn DirectElementGroup::tokens_of_kind(
  self : DirectElementGroup,
  kind : RawKind,
) -> Array[SyntaxToken] {
  self.elements
  .iter()
  .filter_map(elem => {
    match elem {
      SyntaxElement::Token(t) => if t.kind() == kind { Some(t) } else { None }
      SyntaxElement::Node(_) => None
    }
  })
  .collect()
}

///|
/// Child nodes of this group matching `kind`, in source order.
fn DirectElementGroup::children_of_kind(
  self : DirectElementGroup,
  kind : RawKind,
) -> Array[SyntaxNode] {
  self.elements
  .iter()
  .filter_map(elem => {
    match elem {
      SyntaxElement::Node(n) => if n.kind() == kind { Some(n) } else { None }
      SyntaxElement::Token(_) => None
    }
  })
  .collect()
}

///|
/// Shape error for a group-level token check: matched tokens when present,
/// the group span (slot span for an empty group) when none matched.
fn DirectElementGroup::token_error(
  self : DirectElementGroup,
  kind : RawKind,
  matches : Array[SyntaxToken],
  expectation : ProjectionShapeExpectation,
  message~ : String,
) -> ProjectionShapeError {
  let (start, end) = if matches.length() == 0 {
    (self.start, self.end)
  } else {
    (matches[0].start(), matches[matches.length() - 1].end())
  }
  ProjectionShapeError(
    self.parent,
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
/// Shape error for a group-level child check: matched children when present,
/// the group span (slot span for an empty group) when none matched.
fn DirectElementGroup::child_error(
  self : DirectElementGroup,
  kind : RawKind,
  matches : Array[SyntaxNode],
  expectation : ProjectionShapeExpectation,
  message~ : String,
) -> ProjectionShapeError {
  let (start, end) = if matches.length() == 0 {
    (self.start, self.end)
  } else {
    (matches[0].start(), matches[matches.length() - 1].end())
  }
  ProjectionShapeError(
    self.parent,
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
/// Require zero tokens of `kind` in this group.
///
/// Group-level analogue of `SyntaxNode::expect_no_direct_tokens_of_kind`:
/// `node_kind` is the parent node's kind, and the group index belongs in the
/// projection-supplied `message` (e.g. "argument 2: unexpected count").
pub fn DirectElementGroup::expect_no_tokens_of_kind(
  self : DirectElementGroup,
  kind : RawKind,
  message~ : String,
) -> Result[Unit, ProjectionShapeError] {
  let matches = self.tokens_of_kind(kind)
  if matches.length() == 0 {
    Ok(())
  } else {
    Err(self.token_error(kind, matches, ExpectedZero, message~))
  }
}

///|
/// Accept zero or one token of `kind` in this group; reject two or more.
pub fn DirectElementGroup::optional_token_of_kind(
  self : DirectElementGroup,
  kind : RawKind,
  message~ : String,
) -> Result[SyntaxToken?, ProjectionShapeError] {
  let matches = self.tokens_of_kind(kind)
  match matches.length() {
    0 => Ok(None)
    1 => Ok(Some(matches[0]))
    _ => Err(self.token_error(kind, matches, ExpectedOptional, message~))
  }
}

///|
/// Require exactly one token of `kind` in this group. An empty group reports
/// its slot span, so a missing argument is underlined where it should appear.
pub fn DirectElementGroup::required_token_of_kind(
  self : DirectElementGroup,
  kind : RawKind,
  message~ : String,
) -> Result[SyntaxToken, ProjectionShapeError] {
  let matches = self.tokens_of_kind(kind)
  match matches.length() {
    1 => Ok(matches[0])
    _ => Err(self.token_error(kind, matches, ExpectedOne, message~))
  }
}

///|
/// Require zero child nodes of `kind` in this group.
pub fn DirectElementGroup::expect_no_children_of_kind(
  self : DirectElementGroup,
  kind : RawKind,
  message~ : String,
) -> Result[Unit, ProjectionShapeError] {
  let matches = self.children_of_kind(kind)
  if matches.length() == 0 {
    Ok(())
  } else {
    Err(self.child_error(kind, matches, ExpectedZero, message~))
  }
}

///|
/// Accept zero or one child node of `kind` in this group; reject two or more.
pub fn DirectElementGroup::optional_child_of_kind(
  self : DirectElementGroup,
  kind : RawKind,
  message~ : String,
) -> Result[SyntaxNode?, ProjectionShapeError] {
  let matches = self.children_of_kind(kind)
  match matches.length() {
    0 => Ok(None)
    1 => Ok(Some(matches[0]))
    _ => Err(self.child_error(kind, matches, ExpectedOptional, message~))
  }
}

///|
/// Require exactly one child node of `kind` in this group. An empty group
/// reports its slot span, so a missing argument is underlined where it should
/// appear.
pub fn DirectElementGroup::required_child_of_kind(
  self : DirectElementGroup,
  kind : RawKind,
  message~ : String,
) -> Result[SyntaxNode, ProjectionShapeError] {
  let matches = self.children_of_kind(kind)
  match matches.length() {
    1 => Ok(matches[0])
    _ => Err(self.child_error(kind, matches, ExpectedOne, message~))
  }
}
