///|
fn atomic_multi_edit_benchmark_changes(
  source : String,
  block_count : Int,
  edit_count : Int,
  inserted : String,
) -> @text_change.ChangeSet {
  let changes : Array[@text_change.TextChange] = []
  for index in 0..<edit_count {
    let block = (index + 1) * block_count / (edit_count + 1)
    let start = source.find("Paragraph \{block}").unwrap()
    changes.push(
      @text_change.TextChange::ReplaceRange(start~, delete_len=1, inserted~),
    )
  }
  @text_change.ChangeSet::ChangeSet(source_length=source.length(), changes~) catch {
    _ => abort("atomic multi-edit benchmark ChangeSet failed")
  }
}

///|
test "atomic multi-edit: transactional full parse 2500 blocks, 10 edits" (
  b : @bench.T,
) {
  let block_count = 2500
  let source = document_update_benchmark_source(block_count)
  let forward = atomic_multi_edit_benchmark_changes(
    source, block_count, 10, "Z",
  )
  let updated = forward.apply(source).unwrap()
  let backward = atomic_multi_edit_benchmark_changes(
    source, block_count, 10, "P",
  )
  let parser = @loom.new_syntax_parser(
    @core.SourceId("atomic-multi-edit-benchmark"),
    source,
    markdown_grammar.to_syntax_grammar(),
  ) catch {
    _ => abort("atomic multi-edit benchmark parser setup failed")
  }
  let mut forward_next = true
  b.bench(() => {
    if forward_next {
      parser.apply_changes(forward, updated) catch {
        _ => abort("atomic multi-edit benchmark forward failed")
      }
    } else {
      parser.apply_changes(backward, source) catch {
        _ => abort("atomic multi-edit benchmark backward failed")
      }
    }
    b.keep(parser.syntax_tree().read_or_abort())
    forward_next = !forward_next
  })
}
