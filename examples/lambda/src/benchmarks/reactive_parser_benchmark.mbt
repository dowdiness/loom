// ReactiveParser benchmarks: Signal/Memo pipeline overhead and backdating effectiveness.
// All benchmarks use @loom.new_reactive_parser with @lambda.source_file_grammar (the two-memo pipeline).
// Run with: moon bench --package dowdiness/loom/benchmarks --release

///|
/// Cold pipeline: create ReactiveParser + evaluate term() for the first time.
/// Measures full pipeline construction + Signal/Memo wiring + parse cost.
test "parserdb: cold - new + term()" (b : @bench.T) {
  b.bench(fn() {
    let db = @loom.new_reactive_parser(
      "λf.λx.if f x then x + 1 else x - 1", @lambda.source_file_grammar,
    )
    b.keep(db.term())
  })
}

///|
/// Warm pipeline: repeated term() with no source change.
/// Memos are already valid after the first evaluation; subsequent calls
/// only check staleness and return the cached value.
test "parserdb: warm - term() with no source change" (b : @bench.T) {
  let db = @loom.new_reactive_parser(
    "λf.λx.if f x then x + 1 else x - 1", @lambda.source_file_grammar,
  )
  let _ = db.term() // prime: run once so Memos are valid before measuring
  b.bench(fn() { b.keep(db.term()) })
}

///|
/// Signal no-op: set_source() with the same value + term().
/// String::Eq short-circuits Signal::set — no Memo is invalidated.
/// Should be nearly as cheap as the warm path.
test "parserdb: signal no-op - set_source(same) + term()" (b : @bench.T) {
  let source = "λf.λx.if f x then x + 1 else x - 1"
  let db = @loom.new_reactive_parser(source, @lambda.source_file_grammar)
  let _ = db.term() // prime
  b.bench(fn() {
    db.set_source(source) // String::Eq → Signal no-op → Memos stay valid
    b.keep(db.term())
  })
}

///|
/// Full recompute: set_source() with a different value + term().
/// Both cst_memo and term_memo must recompute from scratch.
/// This is the cost of a genuine source edit via the ReactiveParser API.
test "parserdb: full recompute - set_source(new) + term()" (b : @bench.T) {
  let db = @loom.new_reactive_parser(
    "λf.λx.if f x then x + 1 else x - 1", @lambda.source_file_grammar,
  )
  let _ = db.term() // prime
  b.bench(fn() {
    db.set_source("λf.λx.if f x then x + 2 else x - 1")
    let result = db.term()
    db.set_source("λf.λx.if f x then x + 1 else x - 1") // restore for next iteration
    let _ = db.term()
    b.keep(result)
  })
}

///|
/// Undo/redo cycle: alternate between two sources.
/// Neither String::Eq nor CstStage::Eq fires — both directions are full recomputes.
/// Measures the full pipeline cost for a real-world edit+undo pattern.
test "parserdb: undo/redo cycle" (b : @bench.T) {
  let s1 = "λf.λx.if f x then x + 1 else x - 1"
  let s2 = "λf.λx.if f x then x + 2 else x - 1"
  let db = @loom.new_reactive_parser(s1, @lambda.source_file_grammar)
  let _ = db.term()
  b.bench(fn() {
    db.set_source(s2)
    let _ = db.term()
    db.set_source(s1)
    b.keep(db.term())
  })
}

///|
/// Diagnostics path: set_source() to malformed input + diagnostics().
/// Exercises the error path: CstStage with non-empty diagnostics.
test "parserdb: diagnostics - malformed input" (b : @bench.T) {
  let db = @loom.new_reactive_parser("λx.", @lambda.source_file_grammar)
  b.bench(fn() {
    db.set_source("λ" + "x.")
    b.keep(db.diagnostics())
    db.set_source("λx.")
    let _ = db.diagnostics()
  })
}
