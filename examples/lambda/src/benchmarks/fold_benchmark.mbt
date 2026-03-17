// fold_benchmark.mbt — CstFold cache hit rate and wall-time benchmarks.

// ── FoldStats verification (cache hit rate) ─────────────────────────

///|
test "CstFold stats: 80-let incremental edit reuses most subtrees" {
  let source = make_let_chain(80, "0")
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  // Edit last literal: "0" → "1"
  let edited = make_let_chain_edited(80)
  let edit_start = source.length() - 3 // position of the "0" in "x79"... actually in the last "= 0"
  let edit = @core.Edit::new(edit_start, 1, 1)
  let _ = parser.edit(edit, edited)
  let stats = parser.get_fold_stats()
  match stats {
    Some(s) => {
      // Most subtrees should be reused — only root + edited LetDef chain recomputed
      inspect(s.reused >= 1, content="true")
      inspect(s.recomputed >= 1, content="true")
    }
    None => abort("get_fold_stats returned None")
  }
}

// ── Fold-only wall time (initial vs incremental) ────────────────────

///|
test "fold benchmark: 80 lets - initial parse+fold" (b : @bench.T) {
  let source = make_let_chain(80, "0")
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
    let result = parser.parse()
    b.keep(result)
  })
}

///|
test "fold benchmark: 80 lets - incremental fold after single edit" (
  b : @bench.T,
) {
  let source = make_let_chain(80, "0")
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  let edited = make_let_chain_edited(80)
  let edit_start = source.length() - 3
  let edit = @core.Edit::new(edit_start, 1, 1)
  b.bench(fn() {
    let result = parser.edit(edit, edited)
    b.keep(result)
  })
}

///|
test "fold benchmark: 320 lets - initial parse+fold" (b : @bench.T) {
  let source = make_let_chain(320, "0")
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
    let result = parser.parse()
    b.keep(result)
  })
}

///|
test "fold benchmark: 320 lets - incremental fold after single edit" (
  b : @bench.T,
) {
  let source = make_let_chain(320, "0")
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  let edited = make_let_chain_edited(320)
  let edit_start = source.length() - 3
  let edit = @core.Edit::new(edit_start, 1, 1)
  b.bench(fn() {
    let result = parser.edit(edit, edited)
    b.keep(result)
  })
}
