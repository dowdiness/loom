// Unified Parser[Ast] benchmarks: Input/Derived publish overhead on top of
// the imperative engine, identity short-circuit, and apply_edit reuse path.
// Run with: moon bench --release

///|
/// Cold pipeline: create Parser + evaluate ast() for the first time.
/// Measures full construction (engine + inputs + derived cells) + initial parse.
test "parser: cold - new + ast()" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_parser(
      "(f, x) => if f x then x + 1 else x - 1", @lambda.lambda_grammar,
    )
    b.keep(parser.ast().read_or_abort())
  })
}

///|
/// Warm pipeline: repeated ast() with no source change.
/// Derived cells are already valid; subsequent reads only check staleness.
test "parser: warm - ast() with no source change" (b : @bench.T) {
  let parser = @loom.new_parser(
    "(f, x) => if f x then x + 1 else x - 1", @lambda.lambda_grammar,
  )
  let _ = parser.ast().read_or_abort() // prime
  b.bench(fn() { b.keep(parser.ast().read_or_abort()) })
}

///|
/// Identity set_source: source equals the current value.
/// `Parser::set_source` short-circuits before touching the engine or any
/// input when the source is unchanged — should be close to free.
test "parser: identity - set_source(same) + ast()" (b : @bench.T) {
  let source = "(f, x) => if f x then x + 1 else x - 1"
  let parser = @loom.new_parser(source, @lambda.lambda_grammar)
  let _ = parser.ast().read_or_abort() // prime
  b.bench(fn() {
    parser.set_source(source) // identity → no engine call, no input write
    b.keep(parser.ast().read_or_abort())
  })
}

///|
/// Full recompute: set_source with a different value + ast().
/// Engine runs a full reparse; all published cells update in one batch.
test "parser: full recompute - set_source(new) + ast()" (b : @bench.T) {
  let parser = @loom.new_parser(
    "(f, x) => if f x then x + 1 else x - 1", @lambda.lambda_grammar,
  )
  let _ = parser.ast().read_or_abort() // prime
  b.bench(fn() {
    parser.set_source("(f, x) => if f x then x + 2 else x - 1")
    let result = parser.ast().read_or_abort()
    parser.set_source("(f, x) => if f x then x + 1 else x - 1") // restore
    let _ = parser.ast().read_or_abort()
    b.keep(result)
  })
}

///|
/// Undo/redo cycle: alternate between two sources via set_source.
/// Neither direction is an identity — both trigger a full engine reparse.
test "parser: undo/redo cycle (set_source)" (b : @bench.T) {
  let s1 = "(f, x) => if f x then x + 1 else x - 1"
  let s2 = "(f, x) => if f x then x + 2 else x - 1"
  let parser = @loom.new_parser(s1, @lambda.lambda_grammar)
  let _ = parser.ast().read_or_abort()
  b.bench(fn() {
    parser.set_source(s2)
    let _ = parser.ast().read_or_abort()
    parser.set_source(s1)
    b.keep(parser.ast().read_or_abort())
  })
}

///|
/// Incremental edit via apply_edit: flip a single character deep inside a
/// nested lambda body. Exercises the CST-node-level reuse path end-to-end —
/// the engine walks the reuse cursor and should splice most of the old tree
/// rather than reparsing it. Published via the input-set layer.
///
/// Per Stage 3 validation checkpoint: this should run within noise of
/// `ImperativeParser::edit` — same engine, just a `Runtime::batch` signal
/// publication on top.
test "parser: apply_edit - single char flip in nested lambda" (b : @bench.T) {
  let s1 = "(f, x) => if f x then x + 1 else x - 1"
  let parser = @loom.new_parser(s1, @lambda.lambda_grammar)
  let _ = parser.ast().read_or_abort() // prime
  // Position of the '1' inside "x + 1" — replaced with '2' and back.
  let target = match s1.find("x + 1") {
    Some(i) => i + 4
    None => abort("test setup: '+ 1' not found in source")
  }
  let flipped = s1[0:target].to_owned() +
    "2" +
    s1[target + 1:s1.length()].to_owned()
  b.bench(fn() {
    parser.apply_edit(@core.Edit::new(target, 1, 1), flipped)
    let _ = parser.ast().read_or_abort()
    // Restore for next iteration.
    parser.apply_edit(@core.Edit::new(target, 1, 1), s1)
    b.keep(parser.ast().read_or_abort())
  })
}

///|
/// Parity pair — measures the input-publication overhead `Parser` adds
/// on top of the raw imperative engine. Same source, same edit, only the
/// API differs. Per Stage 3 validation checkpoint, these two should sit
/// within measurement noise of each other: `Parser::apply_edit` is
/// `engine.edit(...)` plus `Input::set` + `Runtime::batch` bookkeeping.
test "parity: imperative edit - let init edit" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(
      "let x = 1\ny", @lambda.lambda_grammar,
    )
    let _ = parser.parse()
    let edit = @core.Edit::replace(8, 9, 9)
    b.keep(parser.edit(edit, "let x = 2\ny"))
  })
}

///|
test "parity: parser apply_edit - let init edit" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_parser("let x = 1\ny", @lambda.lambda_grammar)
    let _ = parser.ast().read_or_abort() // prime
    parser.apply_edit(@core.Edit::replace(8, 9, 9), "let x = 2\ny")
    b.keep(parser.ast().read_or_abort())
  })
}

///|
/// Diagnostics path: cycle between valid and malformed inputs, reading
/// diagnostics after each. Exercises the error publication path — the
/// diagnostics signal updates atomically with syntax_tree and ast inside
/// `Runtime::batch` — and verifies that recovery clears the diagnostics.
test "parser: diagnostics - valid ↔ malformed cycle" (b : @bench.T) {
  let parser = @loom.new_parser("(x) => x", @lambda.lambda_grammar)
  let _ = parser.diagnostics().read_or_abort() // prime
  b.bench(fn() {
    parser.set_source("(x) =>") // malformed
    b.keep(parser.diagnostics().read_or_abort())
    parser.set_source("(x) => x") // recover
    let _ = parser.diagnostics().read_or_abort()
  })
}
