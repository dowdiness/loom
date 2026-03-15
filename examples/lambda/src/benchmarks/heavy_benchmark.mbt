// Heavy benchmarks: realistic IDE session simulation.
// Measures parse latency at scale, per-edit latency over long sessions,
// interner growth, and structural sharing effectiveness.
//
// Run with: moon bench --package dowdiness/loom/benchmarks --release

// ─── Source generators ───────────────────────────────────────────────────────

///|
/// Deterministic PRNG (same as differential fuzz tests).
fn heavy_next_seed(seed : Int) -> Int {
  (seed * 1103515245 + 12345) % 2147483647
}

///|
/// Build a large lambda expression with ~200 tokens.
/// Structure: nested if-then-else with lambda bindings and arithmetic.
///
/// Example output shape:
///   λa.λb.if a + b then (λc.if c then c + 1 else c - 1) else (λd.d + 2)
fn make_large_source() -> String {
  let mut s = ""
  // 8 nested lambdas: λa.λb.λc.λd.λe.λf.λg.λh.
  let vars = ["a", "b", "c", "d", "e", "f", "g", "h"]
  for v in vars {
    s = s + "λ" + v + "."
  }
  // Body: chain of if-then-else with arithmetic
  s = s + make_if_chain(vars, 0)
  s
}

///|
fn make_if_chain(vars : Array[String], depth : Int) -> String {
  if depth >= 4 {
    // Base: arithmetic expression using available vars
    let i = depth % vars.length()
    let j = (depth + 1) % vars.length()
    return vars[i] + " + " + vars[j] + " - 1"
  }
  let i = depth % vars.length()
  let j = (depth + 1) % vars.length()
  "if " +
  vars[i] +
  " " +
  vars[j] +
  " then (" +
  "λx." +
  make_if_chain(vars, depth + 1) +
  ") else (" +
  "λy." +
  make_if_chain(vars, depth + 2) +
  ")"
}

///|
/// Build a wide arithmetic chain: 1 + 2 + 3 + ... + n
fn make_wide_arithmetic(n : Int) -> String {
  let mut s = "1"
  for i = 2; i <= n; i = i + 1 {
    s = s + " + " + i.to_string()
  }
  s
}

///|
/// Build repeated lambda applications: f (f (f (... (f x) ...)))
fn make_nested_application(depth : Int) -> String {
  let mut s = "x"
  for _i = 0; _i < depth; _i = _i + 1 {
    s = "f (" + s + ")"
  }
  "λf.λx." + s
}

///|
/// Apply a single-char insert at a position, returning (new_source, edit).
fn slice(s : String, start : Int, end : Int) -> String {
  let res : Result[StringView, Error] = try? s[start:end]
  match res {
    Ok(view) => view.to_string()
    Err(_) => abort("slice out of bounds")
  }
}

///|
fn apply_char_insert(
  source : String,
  pos : Int,
  ch : String,
) -> (String, @core.Edit) {
  let before = slice(source, 0, pos)
  let after = slice(source, pos, source.length())
  let new_source = before + ch + after
  let edit = @core.Edit::insert(pos, ch.length())
  (new_source, edit)
}

///|
/// Apply a single-char replacement at a position.
fn apply_char_replace(
  source : String,
  pos : Int,
  ch : String,
) -> (String, @core.Edit) {
  let before = slice(source, 0, pos)
  let after = slice(source, pos + 1, source.length())
  let new_source = before + ch + after
  let edit = @core.Edit::replace(pos, pos + 1, pos + ch.length())
  (new_source, edit)
}

// ─── Tier 1: Large document parse ────────────────────────────────────────────

///|
/// Benchmark: Initial parse of ~200-token nested lambda expression.
test "heavy: large document - initial parse" (b : @bench.T) {
  let source = make_large_source()
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(
      source, @lambda.source_file_grammar,
    )
    let result = parser.parse()
    b.keep(result)
  })
}

///|
/// Benchmark: Initial parse of 100-term arithmetic chain (~200 tokens).
test "heavy: wide arithmetic 100 terms - initial parse" (b : @bench.T) {
  let source = make_wide_arithmetic(100)
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(
      source, @lambda.source_file_grammar,
    )
    let result = parser.parse()
    b.keep(result)
  })
}

///|
/// Benchmark: Initial parse of deeply nested application (depth 50).
test "heavy: nested application depth 50 - initial parse" (b : @bench.T) {
  let source = make_nested_application(50)
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(
      source, @lambda.source_file_grammar,
    )
    let result = parser.parse()
    b.keep(result)
  })
}

///|
/// Benchmark: CST-level parse of large document (no AST conversion overhead).
test "heavy: large document - cst parse only" (b : @bench.T) {
  let source = make_large_source()
  b.bench(fn() {
    let result = @lambda.parse_source_file(source) catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

// ─── Tier 2: Typing session (100 sequential edits) ──────────────────────────

///|
/// Benchmark: 100 sequential single-char edits at end of large document.
/// Simulates typing a new expression: " + x + y + z + ..."
test "heavy: typing session - 100 edits at end" (b : @bench.T) {
  let base = make_large_source()
  let chars = [
    " ", "+", " ", "x", " ", "+", " ", "y", " ", "+", " ", "z", " ", "+", " ", "1",
    " ", "+", " ", "2",
  ]
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(base, @lambda.source_file_grammar)
    let _ = parser.parse()
    let mut source = base
    for i = 0; i < 100; i = i + 1 {
      let ch = chars[i % chars.length()]
      let pos = source.length()
      let (new_source, edit) = apply_char_insert(source, pos, ch)
      let _ = parser.edit(edit, new_source)
      source = new_source
    }
    b.keep(parser.get_tree())
  })
}

///|
/// Benchmark: 100 sequential single-char edits in middle of large document.
/// Simulates inserting text inside an existing expression.
test "heavy: typing session - 100 edits in middle" (b : @bench.T) {
  let base = make_large_source()
  let mid = base.length() / 2
  let chars = [
    "x", " ", "+", " ", "y", " ", "+", " ", "1", " ", "+", " ", "2", " ", "+", " ",
    "z", " ", "+", " ",
  ]
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(base, @lambda.source_file_grammar)
    let _ = parser.parse()
    let mut source = base
    let mut insert_pos = mid
    for i = 0; i < 100; i = i + 1 {
      let ch = chars[i % chars.length()]
      let (new_source, edit) = apply_char_insert(source, insert_pos, ch)
      let _ = parser.edit(edit, new_source)
      source = new_source
      insert_pos = insert_pos + ch.length()
    }
    b.keep(parser.get_tree())
  })
}

// ─── Tier 3: Refactoring session (variable renames) ──────────────────────────

///|
/// Benchmark: 100 single-char replacements at scattered positions.
/// Simulates renaming variables throughout a large document.
test "heavy: refactoring session - 100 scattered replacements" (b : @bench.T) {
  let base = make_large_source()
  let replacements = ["x", "y", "z", "a", "b", "c", "d", "e"]
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(base, @lambda.source_file_grammar)
    let _ = parser.parse()
    let mut source = base
    let mut seed = 42
    for i = 0; i < 100; i = i + 1 {
      seed = heavy_next_seed(seed)
      let len = source.length()
      if len < 2 {
        continue i
      }
      let pos = seed.abs() % (len - 1)
      let ch = replacements[i % replacements.length()]
      let (new_source, edit) = apply_char_replace(source, pos, ch)
      let _ = parser.edit(edit, new_source)
      source = new_source
    }
    b.keep(parser.get_tree())
  })
}

// ─── Comparison: full reparse (no optimization) vs incremental ───────────────
//
// "Unoptimized" = full reparse from scratch on every edit.
// No TokenBuffer, no ReuseCursor, no Interner, no NodeInterner.
// Just parse(new_source) each time — the naive approach.

///|
/// Benchmark: 100 edits at end — full reparse every time (no incremental).
test "heavy: FULL REPARSE - 100 edits at end" (b : @bench.T) {
  let base = make_large_source()
  let chars = [
    " ", "+", " ", "x", " ", "+", " ", "y", " ", "+", " ", "z", " ", "+", " ", "1",
    " ", "+", " ", "2",
  ]
  b.bench(fn() {
    let mut source = base
    let initial = @lambda.parse(source) catch {
      _ => @lambda.Term::Error("benchmark")
    }
    let mut tree = initial
    for i = 0; i < 100; i = i + 1 {
      let ch = chars[i % chars.length()]
      let pos = source.length()
      let (new_source, _edit) = apply_char_insert(source, pos, ch)
      // Full reparse — no incremental state, no interning
      let t = @lambda.parse(new_source) catch {
        _ => @lambda.Term::Error("benchmark")
      }
      tree = t
      source = new_source
    }
    b.keep(tree)
  })
}

///|
/// Benchmark: 100 edits in middle — full reparse every time (no incremental).
test "heavy: FULL REPARSE - 100 edits in middle" (b : @bench.T) {
  let base = make_large_source()
  let mid = base.length() / 2
  let chars = [
    "x", " ", "+", " ", "y", " ", "+", " ", "1", " ", "+", " ", "2", " ", "+", " ",
    "z", " ", "+", " ",
  ]
  b.bench(fn() {
    let mut source = base
    let initial = @lambda.parse(source) catch { _ => abort("benchmark failed") }
    let mut tree = initial
    let mut insert_pos = mid
    for i = 0; i < 100; i = i + 1 {
      let ch = chars[i % chars.length()]
      let (new_source, _edit) = apply_char_insert(source, insert_pos, ch)
      let t = @lambda.parse(new_source) catch { _ => abort("benchmark failed") }
      tree = t
      source = new_source
      insert_pos = insert_pos + ch.length()
    }
    b.keep(tree)
  })
}

///|
/// Benchmark: 100 scattered replacements — full reparse every time (no incremental).
test "heavy: FULL REPARSE - 100 scattered replacements" (b : @bench.T) {
  let base = make_large_source()
  let replacements = ["x", "y", "z", "a", "b", "c", "d", "e"]
  b.bench(fn() {
    let mut source = base
    let initial = @lambda.parse(source) catch {
      _ => @lambda.Term::Error("benchmark")
    }
    let mut tree = initial
    let mut seed = 42
    for i = 0; i < 100; i = i + 1 {
      seed = heavy_next_seed(seed)
      let len = source.length()
      if len < 2 {
        continue i
      }
      let pos = seed.abs() % (len - 1)
      let ch = replacements[i % replacements.length()]
      let (new_source, _edit) = apply_char_replace(source, pos, ch)
      let t = @lambda.parse(new_source) catch {
        _ => @lambda.Term::Error("benchmark")
      }
      tree = t
      source = new_source
    }
    b.keep(tree)
  })
}

///|
/// Benchmark: Large document initial parse — full reparse baseline (no interning).
test "heavy: FULL REPARSE - large document initial parse" (b : @bench.T) {
  let source = make_large_source()
  b.bench(fn() {
    let result = @lambda.parse(source) catch { _ => abort("benchmark failed") }
    b.keep(result)
  })
}

///|
/// Measure reuse count over a typing session.
/// Local edits at end should reuse most of the tree.
test "heavy: reuse ratio over 50 edits at end" {
  let base = make_large_source()
  let parser = @loom.new_imperative_parser(base, @lambda.source_file_grammar)
  let _ = parser.parse()
  let chars = [" ", "+", " ", "1"]
  let mut source = base
  let mut total_reuse = 0
  let mut total_edits = 0
  for i = 0; i < 50; i = i + 1 {
    let ch = chars[i % chars.length()]
    let pos = source.length()
    let (new_source, edit) = apply_char_insert(source, pos, ch)
    let _ = parser.edit(edit, new_source)
    total_reuse = total_reuse + parser.get_last_reuse_count()
    total_edits = total_edits + 1
    source = new_source
  }
  // Should have some reuse on average (localized edits at end)
  inspect(total_reuse > 0, content="true")
  inspect(total_edits, content="50")
}

// ─── Tier 5: Scaling comparison — incremental vs full reparse ────────────────
//
// Wide arithmetic at increasing sizes (100, 500, 1000 terms).
// Each size compares:
//   - Full reparse baseline (parse, no incremental state)
//   - Incremental single edit near end (best case for reuse)
//   - 50-edit typing session (incremental vs full reparse)

///|
fn bench_incremental_single_edit(source : String, b : @bench.T) -> Unit {
  let len = source.length()
  let last = slice(source, len - 1, len)
  let replacement = if last == "0" { "1" } else { "0" }
  let (new_source, edit) = apply_char_replace(source, len - 1, replacement)
  b.bench(fn() {
    let p = @loom.new_imperative_parser(source, @lambda.source_file_grammar)
    let _ = p.parse()
    let result = p.edit(edit, new_source)
    b.keep(result)
  })
}

///|
fn bench_full_reparse(source : String, b : @bench.T) -> Unit {
  b.bench(fn() {
    let result = @lambda.parse(source) catch { _ => abort("benchmark failed") }
    b.keep(result)
  })
}

///|
fn bench_session_incremental(source : String, n : Int, b : @bench.T) -> Unit {
  let chars = [" ", "+", " ", "1"]
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(
      source, @lambda.source_file_grammar,
    )
    let _ = parser.parse()
    let mut s = source
    for i = 0; i < n; i = i + 1 {
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
fn bench_session_full_reparse(source : String, n : Int, b : @bench.T) -> Unit {
  let chars = [" ", "+", " ", "1"]
  b.bench(fn() {
    let mut s = source
    let initial = @lambda.parse(s) catch {
      _ => @lambda.Term::Error("benchmark")
    }
    let mut tree = initial
    for i = 0; i < n; i = i + 1 {
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

// --- 100 terms (~200 tokens) ---

///|
test "scale: 100 terms - full reparse" (b : @bench.T) {
  bench_full_reparse(make_wide_arithmetic(100), b)
}

///|
test "scale: 100 terms - incremental single edit" (b : @bench.T) {
  bench_incremental_single_edit(make_wide_arithmetic(100), b)
}

///|
test "scale: 100 terms - 50-edit session incremental" (b : @bench.T) {
  bench_session_incremental(make_wide_arithmetic(100), 50, b)
}

///|
test "scale: 100 terms - 50-edit session full reparse" (b : @bench.T) {
  bench_session_full_reparse(make_wide_arithmetic(100), 50, b)
}

// --- 500 terms (~1000 tokens) ---

///|
test "scale: 500 terms - full reparse" (b : @bench.T) {
  bench_full_reparse(make_wide_arithmetic(500), b)
}

///|
test "scale: 500 terms - incremental single edit" (b : @bench.T) {
  bench_incremental_single_edit(make_wide_arithmetic(500), b)
}

///|
test "scale: 500 terms - 50-edit session incremental" (b : @bench.T) {
  bench_session_incremental(make_wide_arithmetic(500), 50, b)
}

///|
test "scale: 500 terms - 50-edit session full reparse" (b : @bench.T) {
  bench_session_full_reparse(make_wide_arithmetic(500), 50, b)
}

// --- 1000 terms (~2000 tokens) ---

///|
test "scale: 1000 terms - full reparse" (b : @bench.T) {
  bench_full_reparse(make_wide_arithmetic(1000), b)
}

///|
test "scale: 1000 terms - incremental single edit" (b : @bench.T) {
  bench_incremental_single_edit(make_wide_arithmetic(1000), b)
}

///|
test "scale: 1000 terms - 50-edit session incremental" (b : @bench.T) {
  bench_session_incremental(make_wide_arithmetic(1000), 50, b)
}

///|
test "scale: 1000 terms - 50-edit session full reparse" (b : @bench.T) {
  bench_session_full_reparse(make_wide_arithmetic(1000), 50, b)
}
