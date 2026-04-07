///|
/// Partial trait — expresses `source → CstStage`.
/// Returns a `CstStage` directly so implementations can set `is_lex_error`
/// explicitly rather than forcing callers to infer it from heuristics.
/// Named `Parseable` to align with the trait vocabulary in `incr/pipeline/`.
pub(open) trait Parseable {
  parse_source(Self, String) -> CstStage
}

///|
/// Token-erased vtable for a language definition.
/// `Ast` is visible at the type level; the token type is erased inside the closures.
pub struct Language[Ast] {
  priv parse_source : (String) -> CstStage
  priv to_ast : (@seam.SyntaxNode) -> Ast
  priv on_lex_error : (String) -> Ast
}

///|
/// Construct a Language directly from closures.
/// Use this when you don't need the Parseable trait pattern.
pub fn[Ast] Language::from_closures(
  parse_source~ : (String) -> CstStage,
  to_ast~ : (@seam.SyntaxNode) -> Ast,
  on_lex_error~ : (String) -> Ast,
) -> Language[Ast] {
  { parse_source, to_ast, on_lex_error }
}

///|
/// Bridge — erases the concrete token type at call site via static dispatch.
/// `T` must implement `Parseable`; the token type disappears into the closure.
pub fn[T : Parseable, Ast] Language::from(
  lang : T,
  to_ast~ : (@seam.SyntaxNode) -> Ast,
  on_lex_error~ : (String) -> Ast,
) -> Language[Ast] {
  { parse_source: fn(s) { lang.parse_source(s) }, to_ast, on_lex_error }
}

///|
/// Green parse stage output — designed for Memo[T : Eq] boundaries.
///
/// `is_lex_error` is set explicitly by `Parseable::parse_source` implementations
/// when the lexer fails before the parser even runs. This avoids fragile
/// heuristics (token_count, diagnostic string prefixes) in generic pipeline code.
///
/// CstNode::Eq uses a cached structural hash (O(1) rejection path),
/// so comparing two CstStage values is very cheap.
/// diagnostics is Array[String] rather than Array[Diagnostic[T]] because
/// Diagnostic[T] does not derive Eq; normalized strings keep the Eq boundary clean.
pub(all) struct CstStage {
  cst : @seam.CstNode
  diagnostics : Array[String]
  is_lex_error : Bool
} derive(Eq, Debug)
