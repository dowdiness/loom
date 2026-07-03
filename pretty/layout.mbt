///|
/// A document tree for width-aware pretty-printing (Wadler-Lindig algorithm).
/// `A` is the annotation type — typically `SyntaxCategory` for syntax highlighting.
/// Build documents with combinators (`text`, `line`, `nest`, `group`, etc.),
/// then render with `render_string` or `render_spans`.
///
/// Every variant carries a cached `fw` (flat-width): the width when rendered flat,
/// or -1 if the subtree contains HardLine (cannot be flattened). Precomputed at
/// construction, so `Group` decisions are O(1).
pub enum Layout[A] {
  /// Identity for Concat — produces no output. fw=0.
  Empty(Int)
  /// Literal text — rendered as-is. Must not contain newlines. fw = s.length().
  Text(String, Int)
  /// Soft break: space in Flat mode, newline + indent in Break mode. fw=1.
  Line(Int)
  /// Unconditional newline regardless of mode. fw = -1 (cannot be flattened).
  HardLine(Int)
  /// Increase indentation by `Int` spaces for nested content. fw = doc.fw.
  Nest(Int, Layout[A], Int)
  /// Sequential composition — render left then right. fw = combine(l.fw, r.fw).
  Concat(Layout[A], Layout[A], Int)
  /// Layout decision point: try rendering content flat. fw = doc.fw.
  Group(Layout[A], Int)
  /// Attach a semantic tag to content. fw = doc.fw.
  Annotate(A, Layout[A], Int)
} derive(Debug, Eq)

///|
pub fn[A] layout_fw(layout : Layout[A]) -> Int {
  match layout {
    Empty(fw) | Text(_, fw) | Line(fw) | HardLine(fw) | Nest(_, _, fw)
    | Concat(_, _, fw) | Group(_, fw) | Annotate(_, _, fw) => fw
  }
}

///|
fn combine_fws(a : Int, b : Int) -> Int {
  if a < 0 || b < 0 {
    -1
  } else {
    a + b
  }
}

///|
fn[A] has_hardline_trait(layout : Layout[A]) -> Bool {
  match layout {
    Empty(_) | Text(_, _) | Line(_) => false
    HardLine(_) => true
    Nest(_, doc, _) => has_hardline_trait(doc)
    Concat(l, r, _) => has_hardline_trait(l) || has_hardline_trait(r)
    Group(doc, _) => has_hardline_trait(doc)
    Annotate(_, doc, _) => has_hardline_trait(doc)
  }
}

///|
pub impl[A : Debug] Show for Layout[A] with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
