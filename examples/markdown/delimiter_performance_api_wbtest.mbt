///|
fn delimiter_performance_new_syntax_parser(
  source_identity : String,
  source : String,
) -> @loom.SyntaxParser {
  @loom.new_syntax_parser(
    @core.SourceId(source_identity),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
}

///|
fn delimiter_performance_full_parse_runner(
  source_identity : String,
  source : String,
) -> () -> @seam.CstNode {
  let source_id = @core.SourceId(source_identity)
  () => {
    let (cst, _) = parse_cst(source_id, source) catch {
      _ => abort("parse failed")
    }
    cst
  }
}
