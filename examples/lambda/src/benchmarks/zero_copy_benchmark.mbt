// Microbenchmarks for zero-copy lexing investigation (issue #61).
// Isolates string allocation cost by varying identifier length
// while keeping parse structure identical.
//
// Run with: moon bench --release -p dowdiness/lambda/benchmarks -f zero_copy_benchmark.mbt

// --- Input generators ---
// All three produce 55 values + 54 "+" operators = 109 tokens + EOF.
// make_token_source() from performance_benchmark.mbt produces integers: "1 + 2 + 3 + ... + 55"

///|
fn make_short_id_source() -> String {
  for i in 1..<55; s = "a" {
    continue s + " + " + (97 + i % 26).unsafe_to_char().to_string()
  } nobreak {
    s
  }
}

///|
fn make_long_id_source() -> String {
  for i in 1..<55; s = "abcdefghijklmnopqrst" {
    for j in 0..<20; id = "" {
      continue id + (97 + (i + j) % 26).to_string()
    } nobreak {
      continue s + " + " + id
    }
  } nobreak {
    s
  }
}

// --- Tokenize-only benchmarks ---
// Isolates lexer string building cost (read_identifier accumulator).

///|
test "zero-copy: tokenize - integers (baseline)" (b : @bench.T) {
  let source = make_token_source()
  b.bench(fn() {
    let result = @lexer.tokenize(source) catch { _ => abort("bench failed") }
    b.keep(result)
  })
}

///|
test "zero-copy: tokenize - short identifiers" (b : @bench.T) {
  let source = make_short_id_source()
  b.bench(fn() {
    let result = @lexer.tokenize(source) catch { _ => abort("bench failed") }
    b.keep(result)
  })
}

///|
test "zero-copy: tokenize - long identifiers" (b : @bench.T) {
  let source = make_long_id_source()
  b.bench(fn() {
    let result = @lexer.tokenize(source) catch { _ => abort("bench failed") }
    b.keep(result)
  })
}

// --- Full parse benchmarks ---
// Measures tokenize + parse + tree build. The difference from tokenize-only
// shows the combined cost of token_text_at extraction + interning + tree build.

///|
test "zero-copy: full parse - integers (baseline)" (b : @bench.T) {
  let source = make_token_source()
  b.bench(fn() {
    let (tree, _) = @lambda.parse_cst(source) catch {
      _ => abort("bench failed")
    }
    b.keep(tree)
  })
}

///|
test "zero-copy: full parse - short identifiers" (b : @bench.T) {
  let source = make_short_id_source()
  b.bench(fn() {
    let (tree, _) = @lambda.parse_cst(source) catch {
      _ => abort("bench failed")
    }
    b.keep(tree)
  })
}

///|
test "zero-copy: full parse - long identifiers" (b : @bench.T) {
  let source = make_long_id_source()
  b.bench(fn() {
    let (tree, _) = @lambda.parse_cst(source) catch {
      _ => abort("bench failed")
    }
    b.keep(tree)
  })
}
