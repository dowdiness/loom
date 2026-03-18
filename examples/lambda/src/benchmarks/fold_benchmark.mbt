// fold_benchmark.mbt — CstFold cache hit rate and wall-time benchmarks.

// ── Helpers ─────────────────────────────────────────────────────────

///|
/// Find the byte offset of the tail literal in a let-chain source.
/// make_let_chain(n, lit) ends with "let x{n-1} = {lit}\nx{n-1}".
/// Returns the position of the first character of {lit}.
fn tail_literal_offset(source : String) -> Int {
  // The literal is at "= X\n" before the final variable reference.
  // Search backwards for "= " and return the position after it.
  let mut i = source.length() - 1
  // Skip past final "x{n-1}"
  while i >= 0 && source[i] != '\n' {
    i = i - 1
  }
  // i is now at the '\n' before the tail variable
  i = i - 1
  // Now find the "= " before the literal
  while i >= 0 && source[i] != '=' {
    i = i - 1
  }
  // i is at '=', literal starts at i + 2 (after "= ")
  i + 2
}

// ── FoldStats verification (cache hit rate) ─────────────────────────

///|
test "CstFold stats: 80-let incremental edit reuses most subtrees" {
  let source = make_let_chain(80, "0")
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  let edited = make_let_chain_edited(80)
  let edit_start = tail_literal_offset(source)
  let edit = @core.Edit::new(edit_start, 1, 1)
  let _ = parser.edit(edit, edited)
  let stats = parser.get_fold_stats().unwrap()
  // 80-let chain: most LetDef subtrees are structurally unchanged after editing
  // the last literal. Expect high reuse, low recompute.
  inspect(stats.reused > stats.recomputed, content="true")
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
  let edit_start = tail_literal_offset(source)
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
  let edit_start = tail_literal_offset(source)
  let edit = @core.Edit::new(edit_start, 1, 1)
  b.bench(fn() {
    let result = parser.edit(edit, edited)
    b.keep(result)
  })
}
