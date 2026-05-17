///|
/// Compact parseable text that roundtrips through the parser.
/// `parse(to_source(term)) == term` must hold.
pub(open) trait Source {
  to_source(Self) -> String
}

///|
/// Width-aware formatted layout with syntax annotations.
/// Use `pretty_print` for String output, `pretty_spans` for editor spans.
pub(open) trait Pretty {
  to_layout(Self) -> Layout[SyntaxCategory]
}

///|
/// Combines all four text representations:
/// Show, Debug, Source (parseable), and Pretty (formatted).
pub(open) trait Printable: Show + Debug + Source + Pretty {}

///|
/// Format any Pretty type as a string with width-aware line breaking.
pub fn[T : Pretty] pretty_print(value : T, width? : Int = 80) -> String {
  render_string(Pretty::to_layout(value), width~)
}

///|
/// Format any Pretty type with width-driven line breaks effectively
/// disabled, suitable for serialization or `Renderable::unparse` impls.
/// Equivalent to `pretty_print(value, width=1_000_000)` — wide enough
/// that every `Group` whose flat layout fits in a million chars stays
/// flat. `HardLine` and ungrouped `Line` still produce newlines (they
/// don't participate in the `Group` flat/break choice), so the result
/// is only guaranteed single-line for layouts that wrap all `Line`s in
/// groups and avoid `HardLine`.
pub fn[T : Pretty] pretty_unparse(value : T) -> String {
  pretty_print(value, width=1_000_000)
}

///|
/// Format any Pretty type as annotated spans for editor rendering.
pub fn[T : Pretty] pretty_spans(
  value : T,
  width? : Int = 80,
) -> Array[(Span, SyntaxCategory)] {
  render_spans(Pretty::to_layout(value), width~)
}
