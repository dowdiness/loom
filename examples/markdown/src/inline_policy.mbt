///|
priv struct SetextInlinePolicy {
  allow_list_marker : Bool
  min_indent : Int
}

///|
fn SetextInlinePolicy::line_is_underline_after_softbreak(
  self : SetextInlinePolicy,
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  setext_underline_depth_after_newline(
    ctx,
    allow_list_marker=self.allow_list_marker,
    min_indent=self.min_indent,
  )
  is Some(_)
}

///|
fn SetextInlinePolicy::continues_paragraph_after_softbreak(
  self : SetextInlinePolicy,
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  !self.line_is_underline_after_softbreak(ctx) &&
  token_continues_paragraph_after_softbreak(ctx.peek_nth(1))
}

///|
priv struct ListItemSetextInlinePolicy {
  allow_ordered_marker : Bool
  setext : SetextInlinePolicy
}

///|
fn ListItemSetextInlinePolicy::continues_paragraph_after_softbreak(
  self : ListItemSetextInlinePolicy,
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  !self.setext.line_is_underline_after_softbreak(ctx) &&
  !(self.allow_ordered_marker &&
  next_ordered_marker_starts_nested_list(ctx, self.setext.min_indent)) &&
  token_can_start_lazy_list_item_continuation(
    ctx.peek_nth(1),
    allow_ordered_marker=self.allow_ordered_marker,
  )
}

///|
priv enum InlineParsePolicy {
  Paragraph
  LineBound
  ListItem(Bool)
  SetextHeading(SetextInlinePolicy)
  ListItemSetextHeading(ListItemSetextInlinePolicy)
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
fn InlineParsePolicy::setext_heading(
  allow_list_marker~ : Bool,
  min_indent~ : Int,
) -> InlineParsePolicy {
  SetextHeading({ allow_list_marker, min_indent })
}

///|
fn InlineParsePolicy::list_item_setext_heading(
  allow_ordered_marker~ : Bool,
  min_indent~ : Int,
) -> InlineParsePolicy {
  // List-item setext probes deliberately reject `ListMarker` underline tokens:
  // nested list markers should keep list precedence once content indentation is met.
  ListItemSetextHeading({
    allow_ordered_marker,
    setext: { allow_list_marker: false, min_indent },
  })
}

///|
fn InlineParsePolicy::allows_ordered_marker(self : InlineParsePolicy) -> Bool {
  match self {
    Paragraph | LineBound | SetextHeading(_) => true
    ListItem(allow_ordered_marker)
    | ListItemSetextHeading({ allow_ordered_marker, .. }) =>
      allow_ordered_marker
  }
}

///|
fn InlineParsePolicy::softbreak_continues(
  self : InlineParsePolicy,
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  match self {
    LineBound => false
    SetextHeading(policy) => policy.continues_paragraph_after_softbreak(ctx)
    ListItem(allow_ordered_marker) =>
      token_can_start_lazy_list_item_continuation(
        ctx.peek_nth(1),
        allow_ordered_marker~,
      )
    ListItemSetextHeading(policy) =>
      policy.continues_paragraph_after_softbreak(ctx)
    Paragraph => token_continues_paragraph_after_softbreak(ctx.peek_nth(1))
  }
}
