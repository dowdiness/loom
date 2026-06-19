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
fn first_unordered_list_marker(text : String) -> UnorderedListMarker? {
  first_token_text(text).bind(unordered_list_marker_from_text)
}

///|
/// Returns true when a run of blank lines is followed by another list item with
/// the same marker metadata as the list's opening marker.
fn blank_line_run_is_followed_by_matching_list_marker(
  ctx : @core.ParserContext[Token, SyntaxKind],
  opening_marker : UnorderedListMarker,
) -> Bool {
  guard ctx.peek() is BlankLine else { return false }
  let checkpoint = ctx.checkpoint()
  while ctx.peek() is BlankLine {
    ctx.emit_token(BlankLineToken)
  }
  let matches = list_marker_matches(ctx, opening_marker)
  ctx.restore(checkpoint)
  matches
}
