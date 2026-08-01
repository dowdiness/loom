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
fn perf_local_edit_work(count : Int) -> (Int, Int, Int, Int) {
  let source = perf_work_paragraph_doc(count)
  let (edited, edit) = perf_work_middle_edit(source)
  let parser = @loom.new_imperative_parser(
    @core.SourceId("markdown-perf-work"),
    source,
    markdown_grammar,
  )
  let _ = parser.parse()
  let snapshot = parser.edit(edit, edited)
  let stats = parser.get_fold_stats().unwrap()
  (snapshot.reuse_count, stats.reused, stats.recomputed, stats.unvisited)
}

///|
test "perf envelope: localized AST work stays bounded across paragraph scale" {
  let small = perf_local_edit_work(10)
  let medium = perf_local_edit_work(100)
  let large = perf_local_edit_work(500)
  inspect(small.0 > 0, content="true")
  inspect(medium.0 > 0, content="true")
  inspect(large.0 > 0, content="true")
  inspect(small.1 > 0, content="true")
  inspect(medium.1 > 0, content="true")
  inspect(large.1 > 0, content="true")
  inspect(medium.2 <= small.2 + 4, content="true")
  inspect(large.2 <= small.2 + 4, content="true")
  inspect(medium.3 <= small.3 + 4, content="true")
  inspect(large.3 <= small.3 + 4, content="true")
}
