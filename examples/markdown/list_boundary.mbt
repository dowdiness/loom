///|
/// Shared unordered-list boundary model for the current narrow CommonMark slice.
///
/// The boundary-bearing value is explicit marker metadata, not raw token text:
/// a list can continue only when the next list marker has the same metadata as
/// the opening marker. The full parser may also continue across blank-line runs
/// when the following marker still matches; block reparse intentionally applies
/// the same marker rule inside a stricter single-node replacement window and may
/// decline blank-line/container-widening edits so the normal incremental path can
/// reparse the affected region.
fn current_unordered_list_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> UnorderedListMarker? {
  match ctx.peek() {
    ListMarker =>
      unordered_list_marker_from_text(ctx.current_token_text().to_owned())
    _ => None
  }
}

///|
/// Returns true when the current token is a list marker with the same explicit
/// marker metadata as the list's opening marker.
fn list_marker_matches(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : UnorderedListMarker,
) -> Bool {
  current_unordered_list_marker(ctx) == Some(opening_marker)
}

///|
fn current_list_marker_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Int? {
  marker_indent_columns_after_optional_indent(
    ctx.current_token_text().to_owned(),
    0,
  )
}

///|
fn current_list_marker_token_width(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Int {
  let text = ctx.current_token_text().to_owned()
  count_indent_columns(text, 0, text.length())
}

///|
fn list_marker_matches_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : UnorderedListMarker,
  min_indent : Int,
) -> Bool {
  list_marker_matches(ctx, opening_marker) &&
  current_list_marker_indent(ctx).map_or(false, indent => indent >= min_indent)
}

///|
fn first_unordered_list_marker(text : String) -> UnorderedListMarker? {
  first_token_text(text).bind(unordered_list_marker_from_text)
}

///|
fn current_ordered_list_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> OrderedListMarker? {
  match ctx.peek() {
    OrderedListMarker(marker) => Some(marker)
    _ => None
  }
}

///|
/// Returns true when the current token is an ordered-list marker with the same
/// delimiter as the list's opening marker. The item number itself does not
/// split a CommonMark ordered list; only the opening marker supplies `start`.
fn ordered_list_marker_matches(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : OrderedListMarker,
) -> Bool {
  current_ordered_list_marker(ctx).map_or(false, marker => {
    marker.delimiter == opening_marker.delimiter
  })
}

///|
fn ordered_list_marker_matches_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : OrderedListMarker,
  min_indent : Int,
) -> Bool {
  ordered_list_marker_matches(ctx, opening_marker) &&
  current_list_marker_indent(ctx).map_or(false, indent => indent >= min_indent)
}

///|
fn blank_line_run_is_followed_by_marker_matching(
  ctx : @core.ParserContext[Token, SyntaxKind],
  matches_marker : (@core.ParserContext[Token, SyntaxKind]) -> Bool,
) -> Bool {
  guard ctx.peek() is BlankLine else { return false }
  let checkpoint = ctx.checkpoint()
  while ctx.peek() is BlankLine {
    ctx.emit_token(BlankLineToken)
  }
  let matches = matches_marker(ctx)
  ctx.restore(checkpoint)
  matches
}

///|
/// Returns true when a run of blank lines is followed by another list item with
/// the same marker metadata as the list's opening marker.
fn blank_line_run_is_followed_by_matching_list_marker_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : UnorderedListMarker,
  min_indent : Int,
) -> Bool {
  blank_line_run_is_followed_by_marker_matching(ctx, ctx => {
    list_marker_matches_at_min_indent(ctx, opening_marker, min_indent) &&
    current_list_marker_indent(ctx).map_or(false, indent => {
      indent <= min_indent + 3
    })
  })
}

///|
fn blank_line_run_is_followed_by_matching_ordered_list_marker_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : OrderedListMarker,
  min_indent : Int,
) -> Bool {
  blank_line_run_is_followed_by_marker_matching(ctx, ctx => {
    ordered_list_marker_matches_at_min_indent(ctx, opening_marker, min_indent) &&
    current_list_marker_indent(ctx).map_or(false, indent => {
      indent <= min_indent + 3
    })
  })
}

///|
fn consume_ordered_list_item_separator_at_min_indent(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : OrderedListMarker,
  min_indent : Int,
) -> Unit {
  if ctx.peek() is Newline {
    ctx.emit_token(NewlineToken)
  }
  if blank_line_run_is_followed_by_matching_ordered_list_marker_at_min_indent(
      ctx, opening_marker, min_indent,
    ) {
    while ctx.peek() is BlankLine {
      ctx.emit_token(BlankLineToken)
    }
  }
}
