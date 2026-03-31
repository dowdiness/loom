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
/// Super trait: a type with all four text representations.
/// Show (derive) + Debug (derive) + Source (parseable) + Pretty (formatted).
pub(open) trait Printable : Show + Debug + Source + Pretty {}

///|
/// Format any Pretty type as a string with width-aware line breaking.
pub fn[T : Pretty] pretty_print(value : T, width~ : Int = 80) -> String {
  render_string(Pretty::to_layout(value), width~)
}

///|
/// Format any Pretty type as annotated spans for editor rendering.
pub fn[T : Pretty] pretty_spans(
  value : T,
  width~ : Int = 80,
) -> Array[(Span, SyntaxCategory)] {
  render_spans(Pretty::to_layout(value), width~)
}
