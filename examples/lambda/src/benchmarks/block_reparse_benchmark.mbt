// Block reparse benchmarks: demonstrates O(block_size) vs O(document_size).
//
// Block reparse is an optimisation where edits inside `{ ... }` blocks reparse
// only the block instead of the full document.  These benchmarks measure:
//   1. Single edit inside a block (should be O(block_size), constant regardless of N)
//   2. Full reparse baseline (scales linearly with N)
//   3. 50-edit session across different blocks
//
// Run with: cd examples/lambda && moon bench --release -p dowdiness/lambda/benchmarks -f block_reparse_benchmark.mbt

// ── Source generator ───────────────────────────────────────────────

///|
/// Build a source with N function definitions using blocks:
///
///   let f0(x) = { let a = x + 0; a }
///   let f1(x) = { let a = x + 1; a }
///   ...
///   let f(N-1)(x) = { let a = x + (N-1); a }
///   f(N-1) 0
///
/// Each definition exercises ParamList, BlockExpr, and arithmetic.
fn make_block_let_chain(n : Int) -> String {
  let segments : Array[String] = []
  for i = 0; i < n; i = i + 1 {
    segments.push("let f\{i}(x) = { let a = x + \{i}; a }\n")
  }
  segments.push("f\{n - 1} 0")
  segments.join("")
}

///|
/// Find the byte position of the number in "x + N" inside the block at index `block_idx`.
/// Returns the start position of the digit(s) of N.
fn find_block_number_pos(source : String, block_idx : Int) -> Int {
  // Search for the pattern "x + <digits>;" — each block has exactly one.
  // We find the (block_idx+1)-th occurrence of "x + " and return the position
  // after it (where the digits start).
  let pattern = "x + "
  let mut count = 0
  let mut pos = 0
  while pos < source.length() - pattern.length() {
    let candidate = slice(source, pos, pos + pattern.length())
    if candidate == pattern {
      if count == block_idx {
        return pos + pattern.length()
      }
      count = count + 1
    }
    pos = pos + 1
  }
  abort("find_block_number_pos: block_idx \{block_idx} not found")
}

///|
/// Length of the decimal representation of a non-negative integer.
fn digit_len(n : Int) -> Int {
  if n < 10 {
    1
  } else if n < 100 {
    2
  } else if n < 1000 {
    3
  } else {
    n.to_string().length()
  }
}

// ── Tier 1: Block reparse — edit inside block ─────────────────────
// The key benchmarks: editing inside a block should be O(block_size),
// not O(document_size). So 80 blocks and 320 blocks should take
// roughly the same time per edit.

///|
test "block-reparse: 80 blocks - edit inside block" (b : @bench.T) {
  let n = 80
  let source = make_block_let_chain(n)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  // Find position of the number inside the last block's "x + N"
  let num_pos = find_block_number_pos(source, n - 1)
  let num_len = digit_len(n - 1)
  // Replace the number with "9"
  let before = slice(source, 0, num_pos)
  let after = slice(source, num_pos + num_len, source.length())
  let edited = before + "9" + after
  let edit = @core.Edit::replace(num_pos, num_pos + num_len, num_pos + 1)
  b.bench(fn() {
    let result = parser.edit(edit, edited)
    // Edit back to original for next iteration
    let _ = parser.edit(
      @core.Edit::replace(num_pos, num_pos + 1, num_pos + num_len),
      source,
    )
    b.keep(result)
  })
}

///|
test "block-reparse: 320 blocks - edit inside block" (b : @bench.T) {
  let n = 320
  let source = make_block_let_chain(n)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  let num_pos = find_block_number_pos(source, n - 1)
  let num_len = digit_len(n - 1)
  let before = slice(source, 0, num_pos)
  let after = slice(source, num_pos + num_len, source.length())
  let edited = before + "9" + after
  let edit = @core.Edit::replace(num_pos, num_pos + num_len, num_pos + 1)
  b.bench(fn() {
    let result = parser.edit(edit, edited)
    let _ = parser.edit(
      @core.Edit::replace(num_pos, num_pos + 1, num_pos + num_len),
      source,
    )
    b.keep(result)
  })
}

// ── Tier 2: Full reparse baseline ──────────────────────────────────
// Full reparse scales linearly with document size. This is the
// comparison point for the block reparse benchmarks above.

///|
test "block-reparse: 80 blocks - full reparse (baseline)" (b : @bench.T) {
  let source = make_block_let_chain(80)
  b.bench(fn() {
    let result = @lambda.parse(source) catch { _ => abort("benchmark failed") }
    b.keep(result)
  })
}

///|
test "block-reparse: 320 blocks - full reparse (baseline)" (b : @bench.T) {
  let source = make_block_let_chain(320)
  b.bench(fn() {
    let result = @lambda.parse(source) catch { _ => abort("benchmark failed") }
    b.keep(result)
  })
}

// ── Tier 3: 50-edit session across different blocks ────────────────
// Simulates an editing session where the user edits inside various blocks.
// Each edit targets a different block (round-robin). Block reparse should
// keep per-edit cost constant regardless of document size.

///|
test "block-reparse: 80 blocks - 50-edit session" (b : @bench.T) {
  let n = 80
  let base = make_block_let_chain(n)
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(base, @lambda.lambda_grammar)
    let _ = parser.parse()
    let mut source = base
    for i = 0; i < 50; i = i + 1 {
      let block_idx = i % n
      let num_pos = find_block_number_pos(source, block_idx)
      let num_len = digit_len(block_idx)
      let replacement = ((i + 1) % 10).to_string()
      let before = slice(source, 0, num_pos)
      let after = slice(source, num_pos + num_len, source.length())
      let edited = before + replacement + after
      let edit = @core.Edit::replace(
        num_pos,
        num_pos + num_len,
        num_pos + replacement.length(),
      )
      let _ = parser.edit(edit, edited)
      source = edited
    }
    b.keep(parser.get_tree())
  })
}

///|
test "block-reparse: 320 blocks - 50-edit session" (b : @bench.T) {
  let n = 320
  let base = make_block_let_chain(n)
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(base, @lambda.lambda_grammar)
    let _ = parser.parse()
    let mut source = base
    for i = 0; i < 50; i = i + 1 {
      let block_idx = i % n
      let num_pos = find_block_number_pos(source, block_idx)
      let num_len = digit_len(block_idx)
      let replacement = ((i + 1) % 10).to_string()
      let before = slice(source, 0, num_pos)
      let after = slice(source, num_pos + num_len, source.length())
      let edited = before + replacement + after
      let edit = @core.Edit::replace(
        num_pos,
        num_pos + num_len,
        num_pos + replacement.length(),
      )
      let _ = parser.edit(edit, edited)
      source = edited
    }
    b.keep(parser.get_tree())
  })
}
