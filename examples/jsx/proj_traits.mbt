// TreeNode + Renderable impls for JsxNode (Task 1.2 Step 6), following
// the json/markdown proj_traits pattern (ADDING_A_LANGUAGE.md Step 1).
//
// same_kind is the load-bearing contract: canopy's @core.reconcile keys
// ProjNode ID preservation off it. Element discriminates on the tag
// (React-style element-type identity — streaming `<di` → `<div` resets
// identity exactly once, at tag completion; markdown's Heading(level)
// precedent), while Text/ExprSpan deliberately ignore content so a
// growing span keeps its ProjNode ID (Design B, "Growing opaque ExprSpan
// identity"). kind_tag returns plain variant names — Phase 2's projection
// tests expect exactly "Element".

///|
const LABEL_MAX : Int = 30

///|
/// Truncate by scalar characters, not UTF-16 code units — a code-unit
/// slice at the cap can split a surrogate pair (labels are display text).
fn truncate_label(text : String) -> String {
  if text.length() <= LABEL_MAX {
    return text
  }
  let buf = StringBuilder::new()
  for c in text.iter().take(LABEL_MAX) {
    buf.write_char(c)
  }
  buf.write_string("...")
  buf.to_string()
}

///|
pub impl @core.TreeNode for JsxNode with fn children(self) {
  match self {
    Root(children~) | Fragment(children~) | Element(children~, ..) => children
    Text(_) | ExprSpan(..) | Error(_) => []
  }
}

///|
pub impl @core.TreeNode for JsxNode with fn same_kind(self, other) {
  match (self, other) {
    (Element(tag=a, ..), Element(tag=b, ..)) => a == b
    (Root(..), Root(..))
    | (Fragment(..), Fragment(..))
    | (Text(_), Text(_))
    | (ExprSpan(..), ExprSpan(..))
    | (Error(_), Error(_)) => true
    _ => false
  }
}

///|
pub impl @core.Renderable for JsxNode with fn kind_tag(self) {
  match self {
    Root(..) => "Root"
    Element(..) => "Element"
    Fragment(..) => "Fragment"
    Text(_) => "Text"
    ExprSpan(..) => "ExprSpan"
    Error(_) => "Error"
  }
}

///|
pub impl @core.Renderable for JsxNode with fn label(self) {
  match self {
    Root(children~) => "[" + children.length().to_string() + " children]"
    Element(tag~, ..) => "<" + tag + ">"
    Fragment(..) => "<>"
    Text(text) => truncate_label(text)
    ExprSpan(raw~) => "{" + truncate_label(raw) + "}"
    Error(message) => truncate_label(message)
  }
}

///|
pub impl @core.Renderable for JsxNode with fn placeholder(_self) {
  "..."
}

///|
/// Quote an attribute string so it re-parses to the same content: `"` by
/// default, `'` when the content contains a double quote, and — when both
/// quote kinds appear — `"` with the doubles backslash-escaped (the
/// lexer's escape rule consumes the next char unconditionally). The
/// escaped form re-parses with the backslash still in the content; full
/// escape/unescape semantics are out of Phase 1's scope.
fn quote_attr_string(content : String) -> String {
  if !content.contains("\"") {
    "\"" + content + "\""
  } else if !content.contains("'") {
    "'" + content + "'"
  } else {
    "\"" + content.replace_all(old="\"", new="\\\"") + "\""
  }
}

///|
fn unparse_attr(attr : JsxAttr) -> String {
  match attr.value {
    StringLit(content) => " " + attr.name + "=" + quote_attr_string(content)
    ExprSpan(raw~) => " " + attr.name + "={" + raw + "}"
    Bare => " " + attr.name
  }
}

///|
/// Normalized JSX source, not byte-faithful to the parse input: childless
/// elements self-close, attribute strings re-quote (see
/// quote_attr_string), truncated forms unparse as their completed shape
/// (the diagnostics carry the truncation fact). Error's payload is
/// recovered source text and passes through unchanged.
///
/// Contract scope: faithful for parser-produced ASTs. A hand-built
/// Text containing `<` or `{` unparses as-is and would re-parse as
/// markup — the lexer's Text runs stop at those characters, so no parse
/// output ever contains them, and JSX has no text-level escape this
/// parser could read back (entity handling is a Phase 3 non-goal).
pub impl @core.Renderable for JsxNode with fn unparse(self) {
  match self {
    Root(children~) => children.map(c => @core.Renderable::unparse(c)).join("")
    Element(tag~, attrs~, children~) => {
      let attr_text = attrs.map(unparse_attr).join("")
      if children.is_empty() {
        "<" + tag + attr_text + "/>"
      } else {
        "<" +
        tag +
        attr_text +
        ">" +
        children.map(c => @core.Renderable::unparse(c)).join("") +
        "</" +
        tag +
        ">"
      }
    }
    Fragment(children~) =>
      "<>" + children.map(c => @core.Renderable::unparse(c)).join("") + "</>"
    Text(text) => text
    ExprSpan(raw~) => "{" + raw + "}"
    Error(text) => text
  }
}
