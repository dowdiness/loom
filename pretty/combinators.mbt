///|
pub fn[A] empty() -> Layout[A] {
  Empty(0)
}

///|
pub fn[A] text(s : String) -> Layout[A] {
  Text(s, s.length())
}

///|
pub fn[A] char(c : Char) -> Layout[A] {
  text(c.to_string())
}

///|
pub fn[A] line() -> Layout[A] {
  Line(1)
}

///|
pub fn[A] hardline() -> Layout[A] {
  HardLine(-1)
}

///|
/// Space in flat mode, newline + indent in break mode.
/// Equivalent to `group(line())` — a one-element group that flattens to a space.
pub fn[A] softline() -> Layout[A] {
  Group(line(), 1)
}

///|
pub fn[A] nest(layout : Layout[A], indent? : Int = 2) -> Layout[A] {
  Nest(indent, layout, layout_fw(layout))
}

///|
pub fn[A] group(doc : Layout[A]) -> Layout[A] {
  Group(doc, layout_fw(doc))
}

///|
pub fn[A] concat(l : Layout[A], r : Layout[A]) -> Layout[A] {
  Concat(l, r, combine_fws(layout_fw(l), layout_fw(r)))
}

///|
pub fn[A] annotate(ann : A, doc : Layout[A]) -> Layout[A] {
  Annotate(ann, doc, layout_fw(doc))
}

///|
pub impl[A] Add for Layout[A] with fn add(self, other) {
  concat(self, other)
}

///|
pub fn[A] separate(sep : Layout[A], docs : Array[Layout[A]]) -> Layout[A] {
  match docs {
    [] => empty()
    [x, .. xs] => xs.iter().fold(init=x, fn(acc, d) { acc + sep + d })
  }
}

///|
pub fn[A] surround(
  left : Layout[A],
  right : Layout[A],
  doc : Layout[A],
) -> Layout[A] {
  left + doc + right
}

///|
pub fn[A] parens(doc : Layout[A]) -> Layout[A] {
  surround(char('('), char(')'), doc)
}

///|
pub fn[A] brackets(doc : Layout[A]) -> Layout[A] {
  surround(char('['), char(']'), doc)
}

///|
pub fn[A] braces(doc : Layout[A]) -> Layout[A] {
  surround(char('{'), char('}'), doc)
}

///|
/// Bracketed block: `l` + indented content + `r`.
/// Flat: `[ content ]` (spaces around content from line()).
/// Broken: `[\n  content\n]` (content indented, delimiters on own lines).
/// Empty content produces `lr` with no interior spaces (e.g., `[]`).
pub fn[A] bracket(l : String, r : String, doc : Layout[A]) -> Layout[A] {
  match doc {
    Empty(_) => group(text(l) + text(r))
    _ => group(text(l) + nest(line() + doc) + line() + text(r))
  }
}
