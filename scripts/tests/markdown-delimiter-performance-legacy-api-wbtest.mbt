///|
fn delimiter_performance_new_syntax_parser(
  _source_identity : String,
  source : String,
) -> @loom.SyntaxParser {
  @loom.new_syntax_parser(source, markdown_grammar.to_syntax_grammar())
}

///|
fn delimiter_performance_full_parse_runner(
  _source_identity : String,
  source : String,
) -> () -> @seam.CstNode {
  () => {
    let (cst, _) = parse_cst(source) catch { _ => abort("parse failed") }
    cst
  }
}
