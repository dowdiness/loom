///|
/// Parse to the placeholder AST and diagnostics.
pub fn parse_moonbit(
  source_id : @core.SourceId,
  source : String,
) -> (MoonbitParseShell, @core.DiagnosticSet) raise Failure {
  let parser = @loom.new_imperative_parser(source_id, source, moonbit_grammar)
  let snapshot = parser.parse()
  (snapshot.ast, snapshot.diagnostics)
}

///|
/// Parse to a CST and diagnostics through the syntax-only grammar boundary.
#warnings("-unused_error_type")
pub fn parse_cst(
  source_id : @core.SourceId,
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise {
  moonbit_syntax_grammar.parse_cst(source_id, source)
}
