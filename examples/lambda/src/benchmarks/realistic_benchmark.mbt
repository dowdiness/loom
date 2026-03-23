// Realistic incremental benchmarks: exercises the full lambda grammar.
//
// Unlike profiling_benchmark.mbt which uses trivial `let x = 0`, these
// benchmarks generate source that combines all grammar features:
// - Block expressions with nested let bindings
// - Lambda expressions with parameters
// - If-then-else with complex conditions
// - Binary operators (arithmetic)
// - Function application (juxtaposition)
// - Parenthesized expressions
// - Multi-parameter function definitions: let f(x, y) = ...
//
// Run with: moon bench --release

///|
/// Generate a realistic definition with all grammar features.
/// Each definition has ~20-40 tokens (vs ~4 for `let x = 0`).
fn make_realistic_def(i : Int) -> String {
  match i % 5 {
    // Block expression with nested lets
    0 =>
      "f\{i} = {\n  let a\{i} = \{i} + \{i + 1}\n  let b\{i} = a\{i} + 1\n  b\{i}\n}"
    // Lambda with if-then-else
    1 => "g\{i} = λx.λy.if x then y + 1 else y - 1"
    // Multi-param function with application
    2 => "h\{i}(x, y) = (λz.z + x) (y + 1)"
    // Nested application with parentheses
    3 => "k\{i} = (λf.λx.f (f x)) (λn.n + 1) \{i}"
    // Nested if with block and arithmetic
    _ => "m\{i}(n) = if n then {\n  let r = n - 1\n  r + r\n} else 0"
  }
}

///|
/// Generate a realistic source file with n definitions.
/// Returns (source, edit_pos) where edit_pos points to the last definition's value.
fn make_realistic_source(n : Int, tail_value : String) -> String {
  let segments : Array[String] = []
  for i = 0; i < n - 1; i = i + 1 {
    segments.push("let " + make_realistic_def(i))
  }
  segments.push("let result = " + tail_value)
  segments.push("result")
  segments.join("\n")
}

///|
/// Find the byte position of the LAST single-char tail value in the source.
/// The source ends with "let result = <tail>\nresult", so the tail char
/// is at len - 1 - "result".length() - 1 (newline) = len - 8.
fn find_tail_edit_pos(source : String) -> Int {
  // "let result = X\nresult" — X is at len - 8
  source.length() - "\nresult".length() - 1
}

///|
/// Find byte position of the first occurrence of a single digit in
/// "let a0 = 0 + 1" (the first block def's first operand).
/// The pattern is: "let f0 = {\n  let a0 = 0 + "
/// We search for the offset of the "1" after "0 + " in the first definition.
fn find_head_edit_pos(source : String) -> Int {
  // First def is "let f0 = {\n  let a0 = 0 + 1\n  ..."
  // "let f0 = {\n  let a0 = 0 + " has length ~28
  // Find "0 + 1" — the "1" is what we edit
  let prefix = "let f0 = {\n  let a0 = 0 + "
  prefix.length() // position of "1"
}

///|
/// Find byte position inside a middle block def's nested let.
/// For n defs, the middle block is at index (n/2) rounded to nearest %5==0.
fn find_middle_block_edit_pos(source : String, n : Int) -> Int {
  // Sum up lengths of defs before the target
  let target_idx = (n / 2 / 5) * 5 // nearest block def (i%5==0)
  let mut pos = 0
  for i = 0; i < target_idx; i = i + 1 {
    pos = pos + ("let " + make_realistic_def(i) + "\n").length()
  }
  // Inside this def: "let fN = {\n  let aN = N + N+1\n  let bN = aN + 1\n  ..."
  // Edit the "1" in "aN + 1" (second line of block)
  let def_prefix = "let f\{target_idx} = {\n  let a\{target_idx} = \{target_idx} + \{target_idx + 1}\n  let b\{target_idx} = a\{target_idx} + "
  pos + def_prefix.length() // position of "1"
}

///|
/// Helper: replace one byte at pos in source string.
fn replace_char_at(source : String, pos : Int, replacement : String) -> String {
  let res_before : Result[StringView, Error] = try? source[:pos]
  let res_after : Result[StringView, Error] = try? source[pos + 1:]
  let before = match res_before {
    Ok(v) => v.to_string()
    Err(_) => abort("slice error")
  }
  let after = match res_after {
    Ok(v) => v.to_string()
    Err(_) => abort("slice error")
  }
  before + replacement + after
}

// ─── 40 realistic defs ───────────────────────────────────────────────────────

///|
test "realistic: 40 defs - full reparse" (b : @bench.T) {
  let source = make_realistic_source(40, "0")
  b.bench(fn() {
    let (cst, _) = @lambda.parse_cst(source) catch { _ => abort("failed") }
    b.keep(cst)
  })
}

///|
test "realistic: 40 defs - incremental (edit tail)" (b : @bench.T) {
  let source = make_realistic_source(40, "0")
  let pos = find_tail_edit_pos(source)
  let edited = replace_char_at(source, pos, "1")
  let edit = @core.Edit::replace(pos, pos + 1, pos + 1)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
test "realistic: 40 defs - incremental (edit head block)" (b : @bench.T) {
  let source = make_realistic_source(40, "0")
  let pos = find_head_edit_pos(source)
  let edited = replace_char_at(source, pos, "2")
  let edit = @core.Edit::replace(pos, pos + 1, pos + 1)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
test "realistic: 40 defs - incremental (edit middle block)" (b : @bench.T) {
  let source = make_realistic_source(40, "0")
  let pos = find_middle_block_edit_pos(source, 40)
  let edited = replace_char_at(source, pos, "2")
  let edit = @core.Edit::replace(pos, pos + 1, pos + 1)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

// ─── 80 realistic defs ───────────────────────────────────────────────────────

///|
test "realistic: 80 defs - full reparse" (b : @bench.T) {
  let source = make_realistic_source(80, "0")
  b.bench(fn() {
    let (cst, _) = @lambda.parse_cst(source) catch { _ => abort("failed") }
    b.keep(cst)
  })
}

///|
test "realistic: 80 defs - incremental (edit tail)" (b : @bench.T) {
  let source = make_realistic_source(80, "0")
  let pos = find_tail_edit_pos(source)
  let edited = replace_char_at(source, pos, "1")
  let edit = @core.Edit::replace(pos, pos + 1, pos + 1)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
test "realistic: 80 defs - incremental (edit middle block)" (b : @bench.T) {
  let source = make_realistic_source(80, "0")
  let pos = find_middle_block_edit_pos(source, 80)
  let edited = replace_char_at(source, pos, "2")
  let edit = @core.Edit::replace(pos, pos + 1, pos + 1)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

// ─── 160 realistic defs ──────────────────────────────────────────────────────

///|
test "realistic: 160 defs - full reparse" (b : @bench.T) {
  let source = make_realistic_source(160, "0")
  b.bench(fn() {
    let (cst, _) = @lambda.parse_cst(source) catch { _ => abort("failed") }
    b.keep(cst)
  })
}

///|
test "realistic: 160 defs - incremental (edit tail)" (b : @bench.T) {
  let source = make_realistic_source(160, "0")
  let pos = find_tail_edit_pos(source)
  let edited = replace_char_at(source, pos, "1")
  let edit = @core.Edit::replace(pos, pos + 1, pos + 1)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
test "realistic: 160 defs - incremental (edit middle block)" (b : @bench.T) {
  let source = make_realistic_source(160, "0")
  let pos = find_middle_block_edit_pos(source, 160)
  let edited = replace_char_at(source, pos, "2")
  let edit = @core.Edit::replace(pos, pos + 1, pos + 1)
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}
