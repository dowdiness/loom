///|
fn document_update_benchmark_source(
  block_count : Int,
  references? : Bool = false,
) -> String {
  let out = StringBuilder::StringBuilder()
  if references {
    out.write_string("[ref]: /a\n\n")
  }
  for index in 0..<block_count {
    out.write_string("Paragraph ")
    out.write_string(index.to_string())
    if references {
      out.write_string(" uses [x][ref].\n\n")
    } else {
      out.write_string(" remains stable.\n\n")
    }
  }
  out.to_string()
}

///|
fn benchmark_document_update_cycle(
  b : @bench.T,
  initial : String,
  operations : Array[(@core.Edit, String)],
) -> Unit {
  let parser = @loom.new_syntax_parser(
    @core.SourceId("document-update-benchmark"),
    initial,
    markdown_grammar.to_syntax_grammar(),
  ) catch {
    _ => abort("document update benchmark parser setup failed")
  }
  let updates = MarkdownDocumentUpdates(parser)
  ignore(updates.document_update())
  let mut index = 0
  b.bench(() => {
    let (edit, source) = operations[index]
    parser.apply_edit(edit, source) catch {
      _ => abort("document update benchmark edit failed")
    }
    b.keep(updates.document_update())
    index = (index + 1) % operations.length()
  })
}

///|
test "Markdown document updates: practical 500-block exact edits" (b : @bench.T) {
  let initial = document_update_benchmark_source(500)
  let position = initial.find("Paragraph 250").unwrap()
  let changed = document_update_replace(initial, position, 1, "Z")
  benchmark_document_update_cycle(b, initial, [
    (@core.Edit::replace(position, position + 1, position + 1), changed),
    (@core.Edit::replace(position, position + 1, position + 1), initial),
  ])
}

///|
test "Markdown document updates: scaling 2500-block exact edits" (b : @bench.T) {
  let initial = document_update_benchmark_source(2500)
  let position = initial.find("Paragraph 1250").unwrap()
  let changed = document_update_replace(initial, position, 1, "Z")
  benchmark_document_update_cycle(b, initial, [
    (@core.Edit::replace(position, position + 1, position + 1), changed),
    (@core.Edit::replace(position, position + 1, position + 1), initial),
  ])
}

///|
test "Markdown document updates: 2500-block insertion fallback" (b : @bench.T) {
  let initial = document_update_benchmark_source(2500)
  let position = initial.find("Paragraph 1250").unwrap()
  let inserted = "Inserted block.\n\n"
  let changed = document_update_replace(initial, position, 0, inserted)
  benchmark_document_update_cycle(b, initial, [
    (@core.Edit::insert(position, inserted.length()), changed),
    (@core.Edit::delete(position, position + inserted.length()), initial),
  ])
}

///|
test "Markdown document updates: 2500-block definition fallback" (b : @bench.T) {
  let initial = document_update_benchmark_source(2500, references=true)
  let position = initial.find("/a").unwrap() + 1
  let changed = document_update_replace(initial, position, 1, "b")
  benchmark_document_update_cycle(b, initial, [
    (@core.Edit::replace(position, position + 1, position + 1), changed),
    (@core.Edit::replace(position, position + 1, position + 1), initial),
  ])
}
