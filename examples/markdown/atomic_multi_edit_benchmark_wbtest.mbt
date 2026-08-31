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
fn bench_atomic_multi_edit(
  b : @bench.T,
  edit_count : Int,
  source_id : String,
) -> Unit {
  let block_count = 2500
  let source = document_update_benchmark_source(block_count)
  let forward = atomic_multi_edit_benchmark_changes(
    source, block_count, edit_count, "Z",
  )
  let updated = forward.apply(source).unwrap()
  let backward = atomic_multi_edit_benchmark_changes(
    source, block_count, edit_count, "P",
  )
  let parser = @loom.new_syntax_parser(
    @core.SourceId(source_id),
    source,
    markdown_grammar.to_syntax_grammar(),
  ) catch {
    _ => abort("atomic multi-edit benchmark parser setup failed")
  }
  let expected_reuse = if edit_count <= 32 { edit_count } else { 0 }
  parser.apply_changes(forward, updated) catch {
    _ => abort("atomic multi-edit benchmark preflight forward failed")
  }
  if parser.snapshot().read_or_abort().reuse_count != expected_reuse {
    abort("atomic multi-edit benchmark selected the wrong forward strategy")
  }
  parser.apply_changes(backward, source) catch {
    _ => abort("atomic multi-edit benchmark preflight backward failed")
  }
  if parser.snapshot().read_or_abort().reuse_count != expected_reuse {
    abort("atomic multi-edit benchmark selected the wrong backward strategy")
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

///|
test "atomic multi-edit: bounded forest 2500 blocks, 10 edits" (b : @bench.T) {
  bench_atomic_multi_edit(b, 10, "atomic-multi-edit-benchmark-10")
}

///|
test "atomic multi-edit: bounded forest 2500 blocks, 32 edits" (b : @bench.T) {
  bench_atomic_multi_edit(b, 32, "atomic-multi-edit-benchmark-32")
}

///|
test "atomic multi-edit: full-parse fallback 2500 blocks, 100 edits" (
  b : @bench.T,
) {
  bench_atomic_multi_edit(b, 100, "atomic-multi-edit-benchmark-100")
}
