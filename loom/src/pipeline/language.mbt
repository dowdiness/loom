///|
/// Green parse stage output — designed for Memo[T : Eq] boundaries.
///
/// `is_lex_error` is set explicitly by the CST-producing stage when the
/// lexer fails before the parser even runs. This avoids fragile heuristics
/// (token_count, diagnostic string prefixes) in generic pipeline code.
///
/// CstNode::Eq uses a cached structural hash (O(1) rejection path),
/// so comparing two CstStage values is very cheap.
/// diagnostics is Array[String] rather than DiagnosticSet because this stage is
/// still the legacy high-level parser boundary; normalized strings keep the Eq
/// boundary clean until ParseSnapshot lands.
pub(all) struct CstStage {
  cst : @seam.CstNode
  diagnostics : Array[String]
  is_lex_error : Bool
} derive(Eq, Debug)
