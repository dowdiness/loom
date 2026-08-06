// Deterministic work counters for the localized-edit performance envelope.

///|
fn perf_work_paragraph_doc(count : Int) -> String {
  let out = StringBuilder::new()
  out.write_string("# Document Title\n\n")
  for i = 0; i < count; i = i + 1 {
    out.write_string(
      "Paragraph \{i + 1} with some content that needs parsing. ",
    )
    out.write_string("This is a *sample* paragraph with **formatting**.\n\n")
  }
  out.to_string()
}

///|
fn perf_work_find_from(source : String, target : String, start : Int) -> Int {
  for i = start; i < source.length() - target.length() + 1; i = i + 1 {
    if source[i:i + target.length()].to_owned() == target {
      return i
    }
  }
  -1
}

///|
fn perf_work_middle_edit(source : String) -> (String, @core.Edit) {
  let pos = perf_work_find_from(source, "sample", source.length() / 2)
  guard pos >= 0 else { abort("middle edit target not found") }
  (
    source[:pos].to_owned() + "S" + source[pos + 1:].to_owned(),
    @core.Edit::replace(pos, pos + 1, pos + 1),
  )
}

///|
test "perf envelope: paragraph corpus byte sizes stay stable" {
  inspect(perf_work_paragraph_doc(10).length(), content="1029")
  inspect(perf_work_paragraph_doc(100).length(), content="10210")
  inspect(perf_work_paragraph_doc(500).length(), content="51410")
}

///|
test "perf envelope: isolated full-parse stages preserve the production result" {
  let source_id = @core.SourceId("markdown-perf-stage-parity")
  let source = perf_work_paragraph_doc(10)
  let (production_cst, production_diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("production parse failed")
  }
  let buffer = perf_new_markdown_buffer(source)
  let (staged_cst, staged_diagnostics, reuse_count) = perf_parse_buffer(
    source_id, source, buffer,
  )
  assert_eq(staged_cst, production_cst)
  assert_eq(buffer.get_diagnostics(), @core.DiagnosticSet::empty())
  assert_eq(staged_diagnostics, production_diagnostics)
  assert_eq(reuse_count, 0)
  let fold = @core.CstFold::new(markdown_fold_node)
  let staged_ast = fold.fold(@seam.SyntaxNode::from_cst(staged_cst))
  assert_eq(staged_ast, parse(source_id, source))
}

///|
fn perf_local_edit_work(count : Int) -> (Int, Int, Int, Int) {
  let source = perf_work_paragraph_doc(count)
  let (edited, edit) = perf_work_middle_edit(source)
  let parser = @loom.new_imperative_parser(
    @core.SourceId("markdown-perf-work"),
    source,
    markdown_grammar,
  )
  let _ = try! parser.parse()
  let snapshot = try! parser.edit(edit, edited)
  let stats = parser.get_fold_stats().unwrap()
  (snapshot.reuse_count, stats.reused, stats.recomputed, stats.unvisited)
}

///|
test "perf envelope: localized AST work stays bounded across paragraph scale" {
  let small = perf_local_edit_work(10)
  let medium = perf_local_edit_work(100)
  let large = perf_local_edit_work(500)
  debug_inspect(small, content="(1, 11, 3, 2)")
  debug_inspect(medium, content="(1, 101, 3, 2)")
  debug_inspect(large, content="(1, 501, 3, 2)")
}
