// Benchmarks for incremental parser performance
// Run with: moon bench --package dowdiness/loom/benchmarks --release

///|
/// Benchmark: Full parse of simple expression
test "full parse - simple" (b : @bench.T) {
  b.bench(fn() {
    let result = @lambda.parse("42") catch { _ => abort("benchmark failed") }
    b.keep(result)
  })
}

///|
/// Benchmark: Full parse of lambda expression
test "full parse - lambda" (b : @bench.T) {
  b.bench(fn() {
    let result = @lambda.parse("λx.x") catch { _ => abort("benchmark failed") }
    b.keep(result)
  })
}

///|
/// Benchmark: Full parse of nested lambdas
test "full parse - nested lambdas" (b : @bench.T) {
  b.bench(fn() {
    let result = @lambda.parse("λf.λx.f (f x)") catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Full parse of arithmetic expression
test "full parse - arithmetic" (b : @bench.T) {
  b.bench(fn() {
    let result = @lambda.parse("1 + 2 - 3 + 4") catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Full parse of complex expression
test "full parse - complex" (b : @bench.T) {
  b.bench(fn() {
    let result = @lambda.parse("λf.λx.if f x then x + 1 else x - 1") catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Tokenization
test "tokenization" (b : @bench.T) {
  b.bench(fn() {
    let result = @lexer.tokenize_layout("λf.λx.f x") catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental parser - initial parse
test "incremental - initial parse" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_imperative_parser("x", @lambda.source_file_grammar)
    let result = parser.parse()
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental parser - small edit
test "incremental - small edit" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_imperative_parser("x", @lambda.source_file_grammar)
    let _ = parser.parse()
    let edit = @core.Edit::insert(1, 4)
    let result = parser.edit(edit, "x + 1")
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental parser - multiple edits
test "incremental - multiple edits" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_imperative_parser("x", @lambda.source_file_grammar)
    let _ = parser.parse()
    let edit1 = @core.Edit::insert(1, 4)
    let _ = parser.edit(edit1, "x + 1")
    let edit2 = @core.Edit::replace(4, 5, 5)
    let result = parser.edit(edit2, "x + 2")
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental parser - replacement edit
test "incremental - replacement" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(
      "λx.x", @lambda.source_file_grammar,
    )
    let _ = parser.parse()
    let edit = @core.Edit::replace(0, 1, 1)
    let result = parser.edit(edit, "\\x.x")
    b.keep(result)
  })
}

///|
/// Benchmark: Damage tracking
test "damage tracking" (b : @bench.T) {
  b.bench(fn() {
    let edit = @core.Edit::insert(4, 4)
    let damage = @incremental.DamageTracker::new(edit)
    b.keep(damage)
  })
}

///|
/// Benchmark: Error recovery - valid input
test "error recovery - valid" (b : @bench.T) {
  b.bench(fn() {
    let result = @lambda.parse("λx.x") catch { _ => abort("benchmark failed") }
    b.keep(result)
  })
}

///|
/// Benchmark: Error recovery - error input
test "error recovery - error" (b : @bench.T) {
  b.bench(fn() {
    let result = @lambda.parse("λ.x") catch {
      _ => @lambda.Term::Error("benchmark")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Full parse of let definition + expression.
test "full parse - let" (b : @bench.T) {
  b.bench(fn() {
    let (_, _) = @lambda.parse_source_file_term("let x = 1\nx") catch {
      _ => abort("benchmark failed")
    }
  })
}

///|
/// Benchmark: Full parse of nested let definitions.
test "full parse - nested let" (b : @bench.T) {
  b.bench(fn() {
    let (_, _) = @lambda.parse_source_file_term("let x = 1\nlet y = x + 1\ny") catch {
      _ => abort("benchmark failed")
    }
  })
}

///|
/// Benchmark: Incremental parser - let body edit.
/// "let x = 1\ny" → "let x = 1\nz": damage at [10,11).
test "incremental - let body edit" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(
      "let x = 1\ny", @lambda.source_file_grammar,
    )
    let _ = parser.parse()
    let edit = @core.Edit::replace(10, 11, 11)
    let result = parser.edit(edit, "let x = 1\nz")
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental parser - let init edit.
/// "let x = 1\ny" → "let x = 2\ny": damage at [8,9).
test "incremental - let init edit" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(
      "let x = 1\ny", @lambda.source_file_grammar,
    )
    let _ = parser.parse()
    let edit = @core.Edit::replace(8, 9, 9)
    let result = parser.edit(edit, "let x = 2\ny")
    b.keep(result)
  })
}
