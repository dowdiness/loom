// Detailed performance benchmarks for incremental parser
// Measures scaling behavior, incremental-state overhead, and token-interning cost.
// Run with: moon bench --package dowdiness/loom/benchmarks --release

///|
/// Benchmark: Parse scaling - small input (5 tokens)
test "parse scaling - small (5 tokens)" (b : @bench.T) {
  b.bench(fn() {
    let result = @lambda.parse_tree("1 + 2") catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Parse scaling - medium input (15 tokens)
test "parse scaling - medium (15 tokens)" (b : @bench.T) {
  b.bench(fn() {
    let result = @lambda.parse_tree("λf.λx.if f x then x + 1 else x - 1") catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Parse scaling - large input (30+ tokens)
test "parse scaling - large (30+ tokens)" (b : @bench.T) {
  b.bench(fn() {
    let result = @lambda.parse_tree(
      "λf.λx.if f x then (λy.y + 1) x else (λz.z - 1) (f x)",
    ) catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental vs Full - tiny edit at start
test "incremental vs full - edit at start" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_incremental_parser(
      "λf.λx.if f x then x + 1 else x - 1", @lambda.lambda_grammar,
    )
    let _ = parser.parse()
    let edit = @core.Edit::replace(0, 1, 1)
    let result = parser.edit(edit, "\\f.λx.if f x then x + 1 else x - 1")
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental vs Full - tiny edit at end
test "incremental vs full - edit at end" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_incremental_parser(
      "λf.λx.if f x then x + 1 else x - 1", @lambda.lambda_grammar,
    )
    let _ = parser.parse()
    let edit = @core.Edit::replace(32, 33, 33)
    let result = parser.edit(edit, "λf.λx.if f x then x + 1 else x - 2")
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental vs Full - edit in middle
test "incremental vs full - edit in middle" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_incremental_parser(
      "λf.λx.if f x then x + 1 else x - 1", @lambda.lambda_grammar,
    )
    let _ = parser.parse()
    let edit = @core.Edit::replace(14, 15, 15)
    let result = parser.edit(edit, "λf.λx.if f x then y + 1 else x - 1")
    b.keep(result)
  })
}

///|
/// Benchmark: Sequential edits - typing simulation
test "sequential edits - typing simulation" (b : @bench.T) {
  b.bench(fn() {
    // Simulate typing by making progressive edits
    let parser1 = @loom.new_incremental_parser("x", @lambda.lambda_grammar)
    let _ = parser1.parse()
    let edit1 = @core.Edit::insert(1, 4)
    let result = parser1.edit(edit1, "x + 1")
    b.keep(result)
  })
}

///|
/// Benchmark: Sequential edits - backspace simulation
test "sequential edits - backspace simulation" (b : @bench.T) {
  b.bench(fn() {
    // Simulate backspacing by deleting text
    let parser = @loom.new_incremental_parser("x + 1", @lambda.lambda_grammar)
    let _ = parser.parse()
    let edit = @core.Edit::delete(2, 5) // Delete " + 1"
    let result = parser.edit(edit, "x")
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental state baseline - repeated parsing
test "incremental state baseline - repeated parsing" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_incremental_parser("λx.x", @lambda.lambda_grammar)
    let _ = parser.parse()

    // Make edit
    let edit = @core.Edit::insert(4, 8)
    let _ = parser.edit(edit, "λx.x + 1")

    // Undo edit (should hit cache ideally)
    let edit2 = @core.Edit::delete(4, 8)
    let _ = parser.edit(edit2, "λx.x")
  })
}

///|
/// Benchmark: Incremental state baseline - similar expressions
test "incremental state baseline - similar expressions" (b : @bench.T) {
  b.bench(fn() {
    let parser1 = @loom.new_incremental_parser("x + 1", @lambda.lambda_grammar)
    let result1 = parser1.parse()
    let parser2 = @loom.new_incremental_parser("x + 2", @lambda.lambda_grammar)
    let result2 = parser2.parse()
    b.keep((result1, result2))
  })
}

///|
/// Benchmark: Memory pressure - large document
test "memory pressure - large document" (b : @bench.T) {
  b.bench(fn() {
    // Build a moderately complex expression (simpler to avoid parsing issues)
    let large_expr = "λf.λx.if f x then (λy.y + 1) x else (λz.z - 1) (f x)"
    let parser = @loom.new_incremental_parser(
      large_expr, @lambda.lambda_grammar,
    )
    let _ = parser.parse()

    // Make small edit - change first variable
    let edit = @core.Edit::replace(3, 4, 4) // Replace 'f' with 'g'
    let new_expr = "λg.λx.if g x then (λy.y + 1) x else (λz.z - 1) (g x)"
    let result = parser.edit(edit, new_expr)
    b.keep(result)
  })
}

///|
/// Benchmark: Worst case - invalidate entire cache
test "worst case - full invalidation" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_incremental_parser(
      "λf.λx.if f x then x + 1 else x - 1", @lambda.lambda_grammar,
    )
    let _ = parser.parse()

    // Change at start affects everything (λ → \)
    let edit = @core.Edit::replace(0, 1, 1)
    let result = parser.edit(edit, "\\f.λx.if f x then x + 1 else x - 1")
    b.keep(result)
  })
}

///|
/// Benchmark: Best case - cosmetic change
test "best case - cosmetic change" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_incremental_parser("x + 1", @lambda.lambda_grammar)
    let _ = parser.parse()

    // Change just the constant
    let edit = @core.Edit::replace(4, 5, 5)
    let result = parser.edit(edit, "x + 2")
    b.keep(result)
  })
}

// --- Phase 1: Incremental Lexer Benchmarks (110 tokens) ---
//
// Generates "1 + 2 + 3 + ... + 55" (110 tokens: 55 integers + 54 plus + EOF, 263 chars).
// Compares full tokenize() vs TokenBuffer.update() for single-char edits.
// Each incremental benchmark includes TokenBuffer::new (which calls tokenize internally),
// so the measured overhead beyond full tokenize reflects the update cost.

///|
fn make_token_source() -> String {
  let mut s = "1"
  for i = 2; i <= 55; i = i + 1 {
    s = s + " + " + i.to_string()
  }
  s
}

///|
fn make_token_source_replace(target : Int) -> String {
  let mut s = if target == 1 { "99" } else { "1" }
  for i = 2; i <= 55; i = i + 1 {
    s = s + " + " + (if i == target { "99" } else { i.to_string() })
  }
  s
}

///|
/// Benchmark: Full tokenization of 110-token input (baseline for incremental comparison)
test "phase1: full tokenize - 110 tokens" (b : @bench.T) {
  let source = make_token_source()
  b.bench(fn() {
    let result = @lexer.tokenize(source) catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental tokenize - replace "1" at start with "99"
/// Edit: position [0,1) → [0,2), adds 1 char
test "phase1: incremental tokenize - edit at start (110 tokens)" (b : @bench.T) {
  let source = make_token_source()
  let new_source = make_token_source_replace(1)
  let edit = @core.Edit::replace(0, 1, 2)
  b.bench(fn() {
    let buf = @core.TokenBuffer::new(
      source,
      tokenize_fn=@lexer.tokenize,
      eof_token=@token.EOF,
    ) catch {
      _ => abort("benchmark failed")
    }
    let result = buf.update(edit, new_source) catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental tokenize - replace "28" at middle with "99"
/// Edit: position [126,128) → [126,128), same-length replacement
test "phase1: incremental tokenize - edit in middle (110 tokens)" (b : @bench.T) {
  let source = make_token_source()
  let new_source = make_token_source_replace(28)
  let edit = @core.Edit::replace(126, 128, 128)
  b.bench(fn() {
    let buf = @core.TokenBuffer::new(
      source,
      tokenize_fn=@lexer.tokenize,
      eof_token=@token.EOF,
    ) catch {
      _ => abort("benchmark failed")
    }
    let result = buf.update(edit, new_source) catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental tokenize - replace "55" at end with "99"
/// Edit: position [261,263) → [261,263), same-length replacement
test "phase1: incremental tokenize - edit at end (110 tokens)" (b : @bench.T) {
  let source = make_token_source()
  let new_source = make_token_source_replace(55)
  let edit = @core.Edit::replace(261, 263, 263)
  b.bench(fn() {
    let buf = @core.TokenBuffer::new(
      source,
      tokenize_fn=@lexer.tokenize,
      eof_token=@token.EOF,
    ) catch {
      _ => abort("benchmark failed")
    }
    let result = buf.update(edit, new_source) catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Full re-tokenize of edited source (comparison: what you'd pay without incremental)
test "phase1: full re-tokenize after edit - 110 tokens" (b : @bench.T) {
  let new_source = make_token_source_replace(28)
  b.bench(fn() {
    let result = @lexer.tokenize(new_source) catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

// --- Full parse with global interning ---
// Interners are now global (process-wide). All parse calls share the same
// token/node deduplication pool, improving over time without per-call setup.

///|
/// Benchmark: parse_cst_recover, small input (global interning always active).
test "parse_cst_recover - small" (b : @bench.T) {
  b.bench(fn() {
    let (tree, _) = @lambda.parse_cst_recover("x + 1") catch {
      _ => abort("benchmark failed")
    }
    b.keep(tree)
  })
}

///|
/// Benchmark: parse_cst_recover, larger input.
test "parse_cst_recover - large" (b : @bench.T) {
  let src = "λf.λx.if f x then (λy.y + 1) x else (λz.z - 1) (f x)"
  b.bench(fn() {
    let (tree, _) = @lambda.parse_cst_recover(src) catch {
      _ => abort("benchmark failed")
    }
    b.keep(tree)
  })
}

// --- Phase 3: cursor-based CST reuse ---
//
// Directly measures the parser-level speedup from subtree reuse.
// Uses parse_cst_recover_with_tokens (no cursor, cursor=None) as the
// baseline with matched cursor-construction overhead inside the timed loop.
// This keeps comparisons focused on reuse behavior rather than cursor setup.
// parse_cst_with_cursor uses a live ReuseCursor so ctx.node() can skip
// unchanged subtrees.  The 110-token corpus (55 integers + 54 plus signs)
// gives 54 reusable IntLiteral nodes for the "edit at end" case and ~54
// reusable nodes for "edit at start" (everything after position 1).
//
// Byte offsets match the Phase 1 token benchmarks above:
//   "55" (last token) : old source [261, 263)
//   "1"  (first token): old source [0, 1)

///|
/// Benchmark: full CST reparse of 110-token input, no cursor (cursor reuse baseline).
/// Same tokens passed directly — no tokenization cost in this measurement.
test "phase3: full CST reparse, no cursor - 110 tokens" (b : @bench.T) {
  let source = make_token_source()
  let (old_tree, _) = @lambda.parse_cst_recover(source) catch {
    _ => abort("setup failed")
  }
  let tokens = @lexer.tokenize(source) catch { _ => abort("setup failed") }
  b.bench(fn() {
    // Match the cursor path's per-iteration setup cost for fair comparison.
    let _ = @lambda.make_reuse_cursor(old_tree, 261, 263, tokens)
    let (tree, _, _) = @lambda.parse_cst_recover_with_tokens(
      source,
      tokens,
      None,
    )
    b.keep(tree)
  })
}

///|
/// Benchmark: cursor reuse — edit at end of 110-token input.
/// "... + 55" → "... + 99": damage covers only the last integer [261, 263).
/// 54 of 55 IntLiteral nodes are outside the damage window → reused via ctx.node().
test "phase3: cursor reuse, edit at end - 110 tokens" (b : @bench.T) {
  let old_source = make_token_source()
  let new_source = make_token_source_replace(55)
  let (old_tree, _) = @lambda.parse_cst_recover(old_source) catch {
    _ => abort("setup failed")
  }
  let new_tokens = @lexer.tokenize(new_source) catch {
    _ => abort("setup failed")
  }
  b.bench(fn() {
    let cursor = @lambda.make_reuse_cursor(old_tree, 261, 263, new_tokens)
    let (tree, _, _) = @lambda.parse_cst_with_cursor(
      new_source, new_tokens, cursor,
    )
    b.keep(tree)
  })
}

///|
/// Benchmark: cursor reuse — edit at start of 110-token input.
/// "1 + 2 + ..." → "99 + 2 + ...": damage covers only the first integer [0, 1).
/// 54 of 55 IntLiteral nodes start after the damage window → reused via ctx.node().
test "phase3: cursor reuse, edit at start - 110 tokens" (b : @bench.T) {
  let old_source = make_token_source()
  let new_source = make_token_source_replace(1)
  let (old_tree, _) = @lambda.parse_cst_recover(old_source) catch {
    _ => abort("setup failed")
  }
  let new_tokens = @lexer.tokenize(new_source) catch {
    _ => abort("setup failed")
  }
  b.bench(fn() {
    let cursor = @lambda.make_reuse_cursor(old_tree, 0, 1, new_tokens)
    let (tree, _, _) = @lambda.parse_cst_with_cursor(
      new_source, new_tokens, cursor,
    )
    b.keep(tree)
  })
}

// --- Phase 4: let expression cursor reuse ---
//
// Measures the reuse benefit enabled by mapping LetKeyword/InKeyword/EqToken
// in syntax_kind_to_token_kind.  Before the fix, the init expression in
// "let x = <init> in <body>" always failed the trailing-context check
// (trailing token = InKeyword was unmapped → None → false) and was reparsed
// on every body edit regardless of whether the init changed.
//
// Byte offsets for "let x = 1 in y" (14 bytes):
//   init IntLiteral(1) : [8, 9)   — trailing context = InKeyword
//   body VarRef("y")   : [13, 14) — trailing context = EOF
//
// Byte offsets for "let x = 1 in let y = 2 in z" (27 bytes):
//   outer init IntLiteral(1) : [8, 9)   — trailing context = InKeyword
//   inner init IntLiteral(2) : [21, 22) — trailing context = InKeyword
//   body VarRef("z")         : [26, 27) — trailing context = EOF

///|
/// Benchmark: full CST reparse of let expression, no cursor (Phase 4 reuse baseline).
/// Cursor construction overhead is included to keep comparisons fair.
test "phase4: let body edit - full reparse, no cursor (baseline)" (b : @bench.T) {
  let old_source = "let x = 1 in y"
  let new_source = "let x = 1 in z"
  let (old_tree, _) = @lambda.parse_cst_recover(old_source) catch {
    _ => abort("setup failed")
  }
  let new_tokens = @lexer.tokenize(new_source) catch {
    _ => abort("setup failed")
  }
  b.bench(fn() {
    let _ = @lambda.make_reuse_cursor(old_tree, 13, 14, new_tokens)
    let (tree, _, _) = @lambda.parse_cst_recover_with_tokens(
      new_source,
      new_tokens,
      None,
    )
    b.keep(tree)
  })
}

///|
/// Benchmark: let body edit with cursor — IntLiteral(1) reused via InKeyword context.
/// "let x = 1 in y" → "let x = 1 in z": damage [13,14).
/// IntLiteral(1) at [8,9) is undamaged; its trailing token InKeyword is now mapped → reuse fires.
test "phase4: let body edit - init IntLiteral reused via cursor" (b : @bench.T) {
  let old_source = "let x = 1 in y"
  let new_source = "let x = 1 in z"
  let (old_tree, _) = @lambda.parse_cst_recover(old_source) catch {
    _ => abort("setup failed")
  }
  let new_tokens = @lexer.tokenize(new_source) catch {
    _ => abort("setup failed")
  }
  b.bench(fn() {
    let cursor = @lambda.make_reuse_cursor(old_tree, 13, 14, new_tokens)
    let (tree, _, _) = @lambda.parse_cst_with_cursor(
      new_source, new_tokens, cursor,
    )
    b.keep(tree)
  })
}

///|
/// Benchmark: let init edit with cursor.
/// "let x = 1 in y" → "let x = 2 in y": damage [8,9) — init changed.
/// LetExpr overlaps damage and is reparsed; body VarRef("y") at [13,14) may still be reused.
test "phase4: let init edit - cursor" (b : @bench.T) {
  let old_source = "let x = 1 in y"
  let new_source = "let x = 2 in y"
  let (old_tree, _) = @lambda.parse_cst_recover(old_source) catch {
    _ => abort("setup failed")
  }
  let new_tokens = @lexer.tokenize(new_source) catch {
    _ => abort("setup failed")
  }
  b.bench(fn() {
    let cursor = @lambda.make_reuse_cursor(old_tree, 8, 9, new_tokens)
    let (tree, _, _) = @lambda.parse_cst_with_cursor(
      new_source, new_tokens, cursor,
    )
    b.keep(tree)
  })
}

///|
/// Benchmark: nested let body edit — both init IntLiterals reused via cursor.
/// "let x = 1 in let y = 2 in z" → "...w": damage [26,27).
/// IntLiteral(1) at [8,9) and IntLiteral(2) at [21,22) both trail InKeyword → both reused.
test "phase4: nested let body edit - multiple inits reused" (b : @bench.T) {
  let old_source = "let x = 1 in let y = 2 in z"
  let new_source = "let x = 1 in let y = 2 in w"
  let (old_tree, _) = @lambda.parse_cst_recover(old_source) catch {
    _ => abort("setup failed")
  }
  let new_tokens = @lexer.tokenize(new_source) catch {
    _ => abort("setup failed")
  }
  b.bench(fn() {
    let cursor = @lambda.make_reuse_cursor(old_tree, 26, 27, new_tokens)
    let (tree, _, _) = @lambda.parse_cst_with_cursor(
      new_source, new_tokens, cursor,
    )
    b.keep(tree)
  })
}
