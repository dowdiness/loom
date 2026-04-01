///|
/// A document tree for width-aware pretty-printing (Wadler-Lindig algorithm).
/// `A` is the annotation type — typically `SyntaxCategory` for syntax highlighting.
/// Build documents with combinators (`text`, `line`, `nest`, `group`, etc.),
/// then render with `render_string` or `render_spans`.
pub enum Layout[A] {
  /// Identity for Concat — produces no output.
  Empty
  /// Literal text — rendered as-is. Must not contain newlines.
  Text(String)
  /// Soft break: space in Flat mode, newline + indent in Break mode.
  /// This is the standard line break — Groups decide whether to flatten it.
  Line
  /// Unconditional newline regardless of mode. Forces any enclosing Group
  /// to break. Also signals flat_width = -1 (document cannot be flattened).
  HardLine
  /// Increase indentation by `Int` spaces for nested content.
  /// Only affects subsequent Line breaks — does not change the current column.
  Nest(Int, Layout[A])
  /// Sequential composition — render left then right.
  Concat(Layout[A], Layout[A])
  /// Layout decision point: try rendering content flat (all Lines become spaces).
  /// If flat_width(content) + trailing suffix fits in remaining width, use Flat mode;
  /// otherwise use Break mode. Nested Groups make independent decisions.
  Group(Layout[A])
  /// Attach a semantic tag to content. Transparent to layout decisions.
  /// Emitted as CAnnStart/CAnnEnd in the Cmd stream for render_spans.
  Annotate(A, Layout[A])
} derive(Show, Eq)
