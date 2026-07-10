// JSX AST — the CstFold target for Phase 2's projection pipeline.
//
// Divergences from the plan's starting-point shape, decided at Step 5
// (recorded in canopy docs/plans/2026-07-09-jsx-incremental-parser-
// generative-ui.md Task 1.2):
// - Root(children): a streaming prefix legally has several roots
//   ("<div/>text"); json's single-child root fold does not fit, and
//   reusing Fragment would conflate `<>...</>` with the document root.
// - JsxAttrValue::Bare: boolean attributes (`<div hidden/>`) and
//   EOF-truncated `<div cla` both produce value-less AttrNodes.
// - StringLit stores unquoted content; diagnostics, not the AST, carry
//   the unterminated-literal fact (Design B case 3).

///|
pub(all) enum JsxNode {
  Root(children~ : Array[JsxNode])
  Element(tag~ : String, attrs~ : Array[JsxAttr], children~ : Array[JsxNode])
  Fragment(children~ : Array[JsxNode])
  Text(String)
  // opaque {...} content, unparsed; string-literal chunks keep their
  // quote characters — they are expression source text
  ExprSpan(raw~ : String)
  Error(String)
} derive(Eq, Debug)

///|
pub(all) struct JsxAttr {
  name : String
  value : JsxAttrValue
} derive(Eq, Debug)

///|
pub fn JsxAttr::JsxAttr(name~ : String, value~ : JsxAttrValue) -> JsxAttr {
  { name, value }
}

///|
pub(all) enum JsxAttrValue {
  StringLit(String)
  ExprSpan(raw~ : String)
  Bare
} derive(Eq, Debug)
