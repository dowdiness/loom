///|
/// Assert that applying one edit incrementally produces the same CST and
/// diagnostics as a fresh full parse of `new_source`.
///
/// This is intended for language-example regression tests around reuse cursors,
/// block reparse, and mode-aware relexing. It accepts a syntax-only grammar so
/// AST folding does not mask CST/diagnostic parity failures. Call
/// `Grammar::to_syntax_grammar` when starting from an AST grammar. The returned
/// value is the incremental reuse count so tests can opt in to optimization-path
/// assertions separately.
pub fn[T : Eq + @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind] assert_incremental_edit_matches_full_parse(
  label : String,
  old_source : String,
  edit : @core.Edit,
  new_source : String,
  grammar : SyntaxGrammar[T, K],
) -> Int {
  let parser = new_syntax_parser(old_source, grammar)
  parser.apply_edit(edit, new_source)
  let incremental = parser.snapshot().read_or_abort()
  let (full_cst, full_diagnostics) = try! grammar.parse_cst(new_source)
  let diffs = @core.tree_diff(incremental.syntax.cst_node(), full_cst)
  if diffs.length() != 0 {
    abort(
      "incremental-vs-full CST mismatch (" +
      label +
      "): tree_diff=\{@debug.to_string(diffs)}",
    )
  }
  if !incremental.diagnostics.equal(full_diagnostics) {
    abort(
      "incremental-vs-full diagnostics mismatch (" +
      label +
      "): incremental=[" +
      incremental.diagnostics.format().join("; ") +
      "]; full=[" +
      full_diagnostics.format().join("; ") +
      "]",
    )
  }
  incremental.reuse_count
}
