///|
#cfg(target="js")
extern "js" fn atomic_retention_gc_available() -> Bool =
  #| () => typeof globalThis.gc === "function" &&
  #|   typeof process?.memoryUsage === "function"

///|
#cfg(target="js")
extern "js" fn atomic_retention_collect() -> Unit =
  #| () => globalThis.gc()

///|
#cfg(target="js")
extern "js" fn atomic_retention_heap_used() -> Int =
  #| () => process.memoryUsage().heapUsed

///|
/// Run the retention assertion with:
/// `NODE_OPTIONS=--expose-gc moon test --release --target js examples/markdown/atomic_multi_edit_retention_wbtest.mbt`.
/// Normal test runs skip when explicit GC is unavailable.
#cfg(target="js")
test "atomic multi-edit does not retain prior roots across 5000 batches" {
  guard atomic_retention_gc_available() else { return }
  let block_count = 2500
  let edit_count = 10
  let source = document_update_benchmark_source(block_count)
  let forward = atomic_multi_edit_benchmark_changes(
    source, block_count, edit_count, "Z",
  )
  let updated = forward.apply(source).unwrap()
  let backward = atomic_multi_edit_benchmark_changes(
    source, block_count, edit_count, "P",
  )
  let parser = @loom.new_syntax_parser(
    @core.SourceId("atomic-multi-edit-retention"),
    source,
    markdown_grammar.to_syntax_grammar(),
  ) catch {
    _ => abort("atomic multi-edit retention parser setup failed")
  }
  let mut forward_next = true
  let mut checkpoint_heap = 0
  for iteration in 0..<5000 {
    if forward_next {
      parser.apply_changes(forward, updated) catch {
        _ => abort("atomic multi-edit retention forward update failed")
      }
    } else {
      parser.apply_changes(backward, source) catch {
        _ => abort("atomic multi-edit retention backward update failed")
      }
    }
    assert_eq(parser.snapshot().read_or_abort().reuse_count, edit_count)
    forward_next = !forward_next
    if (iteration + 1) % 100 == 0 {
      atomic_retention_collect()
    }
    if iteration == 999 {
      atomic_retention_collect()
      checkpoint_heap = atomic_retention_heap_used()
    }
  }
  for _ in 0..<5 {
    atomic_retention_collect()
  }
  let final_heap = atomic_retention_heap_used()
  // Allow runtime and test-runner noise while rejecting linear old-root growth.
  assert_true(final_heap <= checkpoint_heap + 16 * 1024 * 1024)
  ignore(parser.syntax_tree().read_or_abort())
}
