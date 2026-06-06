///|
/// Parse to the placeholder AST and diagnostics.
pub fn parse_moonbit(
  source : String,
) -> (MoonbitParseShell, @core.DiagnosticSet) {
  let parser = @loom.new_imperative_parser(source, moonbit_grammar)
  let snapshot = parser.parse()
  (snapshot.ast, snapshot.diagnostics)
}

///|
/// Parse to a CST and diagnostics through the grammar boundary.
#warnings("-unused_error_type")
pub fn parse_cst(
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError {
  moonbit_grammar.parse_cst(source)
}
