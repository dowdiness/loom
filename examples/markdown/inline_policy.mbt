///|
priv enum InlineParsePolicy {
  Paragraph
  LineBound
  ListItem(Bool)
  SetextHeading
  ListItemSetextHeading(Bool)
}

///|
fn InlineParsePolicy::paragraph() -> InlineParsePolicy {
  Paragraph
}

///|
fn InlineParsePolicy::line_bound() -> InlineParsePolicy {
  LineBound
}

///|
fn InlineParsePolicy::list_item(
  allow_ordered_marker~ : Bool,
) -> InlineParsePolicy {
  ListItem(allow_ordered_marker)
}

///|
fn InlineParsePolicy::setext_heading() -> InlineParsePolicy {
  SetextHeading
}

///|
fn InlineParsePolicy::list_item_setext_heading(
  allow_ordered_marker~ : Bool,
) -> InlineParsePolicy {
  ListItemSetextHeading(allow_ordered_marker)
}

///|
fn InlineParsePolicy::allows_ordered_marker(self : InlineParsePolicy) -> Bool {
  match self {
    Paragraph | LineBound | SetextHeading => true
    ListItem(allow_ordered_marker)
    | ListItemSetextHeading(allow_ordered_marker) =>
      allow_ordered_marker
  }
}

