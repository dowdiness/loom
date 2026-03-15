// Let-chain benchmarks: matches the CRDT editor's actual workload.
// The editor generates "let x0 = 0 in let x1 = 0 in ... let xN = T in xN".
// Measures scaling at 80 lets (medium) and 320 lets (large) — the same sizes
// used in the Rabbita perf harness.
//
// Run with: cd examples/lambda && moon bench --release -p dowdiness/lambda/benchmarks -f let_chain_benchmark.mbt
//
// ## Scaling characteristics
//
// Let chains form a right-recursive tree: each LetExpr node wraps the rest of
// the chain as its body child. This is the worst case for any algorithm whose
// per-node cost depends on subtree depth.
//
// Key finding (2026-03-14): Before adding `physical_equal` to `CstNode::Eq`,
// the node interner's equality check was O(subtree) per node, leading to
// O(n²) total parse time. With the fix, scaling is near-linear:
//
//   | Benchmark (initial parse) | Before  | After  | Speedup |
//   |---------------------------|---------|--------|---------|
//   | 80 lets                   | 310 µs  | 137 µs | 2.3x    |
//   | 320 lets                  | 3.72 ms | 662 µs | 5.6x    |
//   | 320/80 scaling ratio      | 12x     | 4.8x   | —       |
//
// See ADR: docs/decisions/2026-03-14-physical-equal-interner.md

// ── Source generators ───────────────────────────────────────────────

///|
fn make_let_chain(n : Int, tail_literal : String) -> String {
  let segments : Array[String] = []
  for i = 0; i < n - 1; i = i + 1 {
    segments.push("let x\{i} = 0\n")
  }
  segments.push("let x\{n - 1} = \{tail_literal}\nx\{n - 1}")
  segments.join("")
}

///|
fn make_let_chain_edited(n : Int) -> String {
  make_let_chain(n, "1")
}

// ── Tier 1: Initial parse ───────────────────────────────────────────

///|
test "let-chain: 80 lets - initial parse" (b : @bench.T) {
  let source = make_let_chain(80, "0")
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
    let result = parser.parse()
    b.keep(result)
  })
}

///|
test "let-chain: 320 lets - initial parse" (b : @bench.T) {
  let source = make_let_chain(320, "0")
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
    let result = parser.parse()
    b.keep(result)
  })
}

// ── Tier 2: Incremental single edit (tail literal change) ───────────

///|
test "let-chain: 80 lets - incremental single edit at tail" (b : @bench.T) {
  let source = make_let_chain(80, "0")
  let edited = make_let_chain_edited(80)
  let edit_pos = source.length() - "0\nx79".length()
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
    let _ = parser.parse()
    let result = parser.edit(edit, edited)
    b.keep(result)
  })
}

///|
test "let-chain: 320 lets - incremental single edit at tail" (b : @bench.T) {
  let source = make_let_chain(320, "0")
  let edited = make_let_chain_edited(320)
  let edit_pos = source.length() - "0\nx319".length()
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
    let _ = parser.parse()
    let result = parser.edit(edit, edited)
    b.keep(result)
  })
}

// ── Tier 2b: Edit-only (initial parse outside bench loop) ────────────
// Isolates the incremental edit cost from the initial parse cost.

///|
test "let-chain: 80 lets - edit-only at tail" (b : @bench.T) {
  let source = make_let_chain(80, "0")
  let edited = make_let_chain_edited(80)
  let edit_pos = source.length() - "0\nx79".length()
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  // Reset to original so each bench iteration starts from the same state
  b.bench(fn() {
    let _ = parser.edit(edit, edited)
    // Edit back to original for next iteration
    let _ = parser.edit(
      @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1),
      source,
    )
    b.keep(parser.get_tree())
  })
}

///|
test "let-chain: 320 lets - edit-only at tail" (b : @bench.T) {
  let source = make_let_chain(320, "0")
  let edited = make_let_chain_edited(320)
  let edit_pos = source.length() - "0\nx319".length()
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  b.bench(fn() {
    let _ = parser.edit(edit, edited)
    let _ = parser.edit(
      @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1),
      source,
    )
    b.keep(parser.get_tree())
  })
}

// ── Tier 3: Full reparse comparison ─────────────────────────────────

///|
test "let-chain: 80 lets - full reparse" (b : @bench.T) {
  let source = make_let_chain(80, "0")
  b.bench(fn() {
    let result = @lambda.parse(source) catch { _ => abort("benchmark failed") }
    b.keep(result)
  })
}

///|
test "let-chain: 320 lets - full reparse" (b : @bench.T) {
  let source = make_let_chain(320, "0")
  b.bench(fn() {
    let result = @lambda.parse(source) catch { _ => abort("benchmark failed") }
    b.keep(result)
  })
}

// ── Tier 4: Typing session (50 edits at end) ────────────────────────

///|
test "let-chain: 80 lets - 50-edit session incremental" (b : @bench.T) {
  let source = make_let_chain(80, "0")
  let chars = [" ", "+", " ", "1"]
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
    let _ = parser.parse()
    let mut s = source
    for i = 0; i < 50; i = i + 1 {
      let ch = chars[i % chars.length()]
      let pos = s.length()
      let (new_s, edit) = apply_char_insert(s, pos, ch)
      let _ = parser.edit(edit, new_s)
      s = new_s
    }
    b.keep(parser.get_tree())
  })
}

///|
test "let-chain: 80 lets - 50-edit session full reparse" (b : @bench.T) {
  let source = make_let_chain(80, "0")
  let chars = [" ", "+", " ", "1"]
  b.bench(fn() {
    let mut s = source
    let initial = @lambda.parse(s) catch {
      _ => @lambda.Term::Error("benchmark")
    }
    let mut tree = initial
    for i = 0; i < 50; i = i + 1 {
      let ch = chars[i % chars.length()]
      let pos = s.length()
      let (new_s, _edit) = apply_char_insert(s, pos, ch)
      let t = @lambda.parse(new_s) catch {
        _ => @lambda.Term::Error("benchmark")
      }
      tree = t
      s = new_s
    }
    b.keep(tree)
  })
}

///|
test "let-chain: 320 lets - 50-edit session incremental" (b : @bench.T) {
  let source = make_let_chain(320, "0")
  let chars = [" ", "+", " ", "1"]
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
    let _ = parser.parse()
    let mut s = source
    for i = 0; i < 50; i = i + 1 {
      let ch = chars[i % chars.length()]
      let pos = s.length()
      let (new_s, edit) = apply_char_insert(s, pos, ch)
      let _ = parser.edit(edit, new_s)
      s = new_s
    }
    b.keep(parser.get_tree())
  })
}

///|
test "let-chain: 320 lets - 50-edit session full reparse" (b : @bench.T) {
  let source = make_let_chain(320, "0")
  let chars = [" ", "+", " ", "1"]
  b.bench(fn() {
    let mut s = source
    let initial = @lambda.parse(s) catch {
      _ => @lambda.Term::Error("benchmark")
    }
    let mut tree = initial
    for i = 0; i < 50; i = i + 1 {
      let ch = chars[i % chars.length()]
      let pos = s.length()
      let (new_s, _edit) = apply_char_insert(s, pos, ch)
      let t = @lambda.parse(new_s) catch {
        _ => @lambda.Term::Error("benchmark")
      }
      tree = t
      s = new_s
    }
    b.keep(tree)
  })
}

// ── Tier 5: Reuse count inspection ──────────────────────────────────

///|
test "let-chain: 80 lets - reuse count for tail edit" {
  let source = make_let_chain(80, "0")
  let edited = make_let_chain_edited(80)
  let edit_pos = source.length() - "0\nx79".length()
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  let _ = parser.edit(edit, edited)
  let reuse = parser.get_last_reuse_count()
  // With let-chain structure, many let-init subtrees should be reusable
  println("80-let reuse count: \{reuse}")
  inspect(reuse >= 0, content="true")
}

///|
test "let-chain: 320 lets - reuse count for tail edit" {
  let source = make_let_chain(320, "0")
  let edited = make_let_chain_edited(320)
  let edit_pos = source.length() - "0\nx319".length()
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  let _ = parser.edit(edit, edited)
  let reuse = parser.get_last_reuse_count()
  println("320-let reuse count: \{reuse}")
  inspect(reuse >= 0, content="true")
}
