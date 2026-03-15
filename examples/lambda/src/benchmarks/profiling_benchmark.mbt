// Profiling benchmarks: isolate overhead sources in the incremental parse path.
//
// Strategy: measure each sub-operation separately using the public API.
// Compare tokenize-only, parse-only, and full incremental to find the bottleneck.
// Then isolate tree-build cost by constructing event streams with ReuseNode.
//
// Run with: moon bench --release -f profiling_benchmark.mbt

///|
fn make_profile_source(n : Int, tail : String) -> String {
  let segments : Array[String] = []
  for i = 0; i < n - 1; i = i + 1 {
    segments.push("let x\{i} = 0")
  }
  segments.push("let x\{n - 1} = \{tail}")
  segments.push("x\{n - 1}")
  segments.join("\n")
}

///|
/// Baseline: tokenize only (no parse, no tree build).
test "profile: 80 lets - tokenize only" (b : @bench.T) {
  let source = make_profile_source(80, "1")
  b.bench(fn() {
    let tokens = @lexer.tokenize(source) catch { _ => abort("lex failed") }
    b.keep(tokens)
  })
}

///|
/// Full reparse: tokenize + parse + tree build (no cursor, no reuse).
test "profile: 80 lets - full reparse" (b : @bench.T) {
  let source = make_profile_source(80, "1")
  b.bench(fn() {
    let (cst, _) = @lambda.parse_cst(source) catch { _ => abort("failed") }
    b.keep(cst)
  })
}

///|
/// Full incremental: tokenize update + cursor + parse with reuse + tree build.
test "profile: 80 lets - incremental (edit tail)" (b : @bench.T) {
  let source = make_profile_source(80, "0")
  let edited = make_profile_source(80, "1")
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  let edit_pos = source.length() - "0\nx79".length()
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    // Reset for next iteration
    let _ = parser.edit(edit, source)
  })
}

///|
/// Incremental with edit at HEAD (first LetDef).
/// If reuse works, should only reparse LetDef[0], reuse LetDef[1..79]+expr.
test "profile: 80 lets - incremental (edit head)" (b : @bench.T) {
  let source = make_profile_source(80, "0")
  let mut edited = "let x0 = 1"
  for i = 1; i < 79; i = i + 1 {
    edited = edited + "\nlet x\{i} = 0"
  }
  edited = edited + "\nlet x79 = 0\nx79"
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  let edit = @core.Edit::replace(9, 10, 10) // Replace "0" with "1" in x0's init
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
/// Same measurements at 320 lets for scaling.
test "profile: 320 lets - tokenize only" (b : @bench.T) {
  let source = make_profile_source(320, "1")
  b.bench(fn() {
    let tokens = @lexer.tokenize(source) catch { _ => abort("lex failed") }
    b.keep(tokens)
  })
}

///|
test "profile: 320 lets - full reparse" (b : @bench.T) {
  let source = make_profile_source(320, "1")
  b.bench(fn() {
    let (cst, _) = @lambda.parse_cst(source) catch { _ => abort("failed") }
    b.keep(cst)
  })
}

///|
test "profile: 320 lets - incremental (edit tail)" (b : @bench.T) {
  let source = make_profile_source(320, "0")
  let edited = make_profile_source(320, "1")
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  let edit_pos = source.length() - "0\nx319".length()
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
test "profile: 320 lets - incremental (edit head)" (b : @bench.T) {
  let source = make_profile_source(320, "0")
  let mut edited = "let x0 = 1"
  for i = 1; i < 319; i = i + 1 {
    edited = edited + "\nlet x\{i} = 0"
  }
  edited = edited + "\nlet x319 = 0\nx319"
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  let edit = @core.Edit::replace(9, 10, 10)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

// ─── Tree-build isolation ──────────────────────────────────────────────────
// Measure build_tree cost with normal events vs ReuseNode events.
// This isolates the rebuild_subtree overhead from the grammar/cursor overhead.

///|
/// Helper: serialize a CstNode into StartNode/Token/FinishNode events.
fn serialize_node(node : @seam.CstNode, out : Array[@seam.ParseEvent]) -> Unit {
  out.push(@seam.ParseEvent::StartNode(node.kind))
  for child in node.children {
    match child {
      @seam.CstElement::Token(t) =>
        out.push(@seam.ParseEvent::Token(t.kind, t.text))
      @seam.CstElement::Node(n) => serialize_node(n, out)
    }
  }
  out.push(@seam.ParseEvent::FinishNode)
}

///|
/// Tree build with normal events (no ReuseNode) — baseline tree-build cost.
test "profile: 80 lets - tree build (normal events)" (b : @bench.T) {
  let source = make_profile_source(80, "1")
  let (cst, _) = @lambda.parse_cst(source) catch { _ => abort("failed") }
  // Serialize CST into normal events
  let events : Array[@seam.ParseEvent] = []
  for child in cst.children {
    match child {
      @seam.CstElement::Token(t) =>
        events.push(@seam.ParseEvent::Token(t.kind, t.text))
      @seam.CstElement::Node(n) => serialize_node(n, events)
    }
  }
  let root_kind = cst.kind
  b.bench(fn() {
    let tree = @seam.build_tree(events, root_kind)
    b.keep(tree)
  })
}

///|
/// Tree build with ReuseNode events — measures rebuild_subtree overhead.
test "profile: 80 lets - tree build (ReuseNode events)" (b : @bench.T) {
  let source = make_profile_source(80, "1")
  let (cst, _) = @lambda.parse_cst(source) catch { _ => abort("failed") }
  let events : Array[@seam.ParseEvent] = []
  for child in cst.children {
    match child {
      @seam.CstElement::Token(t) =>
        events.push(@seam.ParseEvent::Token(t.kind, t.text))
      @seam.CstElement::Node(n) =>
        events.push(@seam.ParseEvent::ReuseNode(n))
    }
  }
  let root_kind = cst.kind
  b.bench(fn() {
    let tree = @seam.build_tree(events, root_kind)
    b.keep(tree)
  })
}

///|
test "profile: 320 lets - tree build (normal events)" (b : @bench.T) {
  let source = make_profile_source(320, "1")
  let (cst, _) = @lambda.parse_cst(source) catch { _ => abort("failed") }
  let events : Array[@seam.ParseEvent] = []
  for child in cst.children {
    match child {
      @seam.CstElement::Token(t) =>
        events.push(@seam.ParseEvent::Token(t.kind, t.text))
      @seam.CstElement::Node(n) => serialize_node(n, events)
    }
  }
  let root_kind = cst.kind
  b.bench(fn() {
    let tree = @seam.build_tree(events, root_kind)
    b.keep(tree)
  })
}

///|
test "profile: 320 lets - tree build (ReuseNode events)" (b : @bench.T) {
  let source = make_profile_source(320, "1")
  let (cst, _) = @lambda.parse_cst(source) catch { _ => abort("failed") }
  let events : Array[@seam.ParseEvent] = []
  for child in cst.children {
    match child {
      @seam.CstElement::Token(t) =>
        events.push(@seam.ParseEvent::Token(t.kind, t.text))
      @seam.CstElement::Node(n) =>
        events.push(@seam.ParseEvent::ReuseNode(n))
    }
  }
  let root_kind = cst.kind
  b.bench(fn() {
    let tree = @seam.build_tree(events, root_kind)
    b.keep(tree)
  })
}

// ─── Subtree depth experiment ──────────────────────────────────────────────
// Test whether incremental wins when reused subtrees are deeper.

///|
/// Generate N LetDefs with complex init expressions (deeper subtrees).
/// Each init is a nested binary expression: "1 + 2 + 3 + ... + depth"
fn make_deep_let_chain(n : Int, depth : Int, tail : String) -> String {
  let segments : Array[String] = []
  for i = 0; i < n; i = i + 1 {
    let mut expr = "1"
    for j = 2; j <= depth; j = j + 1 {
      expr = expr + " + \{j}"
    }
    segments.push("let x\{i} = \{expr}")
  }
  segments.push(tail)
  segments.join("\n")
}

///|
/// 20 LetDefs with depth-10 inits. Edit the tail expression.
test "profile: 20 deep lets - full reparse" (b : @bench.T) {
  let source = make_deep_let_chain(20, 10, "x0")
  b.bench(fn() {
    let (cst, _) = @lambda.parse_cst(source) catch { _ => abort("failed") }
    b.keep(cst)
  })
}

///|
test "profile: 20 deep lets - incremental (edit tail)" (b : @bench.T) {
  let source = make_deep_let_chain(20, 10, "x0")
  let edited = make_deep_let_chain(20, 10, "x1")
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  let edit_pos = source.length() - 2 // change "x0" to "x1"
  let edit = @core.Edit::replace(edit_pos, edit_pos + 2, edit_pos + 2)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
/// 20 LetDefs with depth-20 inits.
test "profile: 20 very deep lets - full reparse" (b : @bench.T) {
  let source = make_deep_let_chain(20, 20, "x0")
  b.bench(fn() {
    let (cst, _) = @lambda.parse_cst(source) catch { _ => abort("failed") }
    b.keep(cst)
  })
}

///|
test "profile: 20 very deep lets - incremental (edit tail)" (b : @bench.T) {
  let source = make_deep_let_chain(20, 20, "x0")
  let edited = make_deep_let_chain(20, 20, "x1")
  let parser = @loom.new_imperative_parser(source, @lambda.lambda_grammar)
  let _ = parser.parse()
  let edit_pos = source.length() - 2
  let edit = @core.Edit::replace(edit_pos, edit_pos + 2, edit_pos + 2)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

// ─── re_intern_subtree isolation ───────────────────────────────────────────

///|
/// Tree build with build_tree (no interning) — baseline.
test "profile: 20 deep lets - build_tree (ReuseNode)" (b : @bench.T) {
  let source = make_deep_let_chain(20, 10, "x0")
  let (cst, _) = @lambda.parse_cst(source) catch { _ => abort("failed") }
  let events : Array[@seam.ParseEvent] = []
  for child in cst.children {
    match child {
      @seam.CstElement::Token(t) =>
        events.push(@seam.ParseEvent::Token(t.kind, t.text))
      @seam.CstElement::Node(n) =>
        events.push(@seam.ParseEvent::ReuseNode(n))
    }
  }
  let root_kind = cst.kind
  b.bench(fn() {
    let tree = @seam.build_tree(events, root_kind)
    b.keep(tree)
  })
}

///|
/// Tree build with build_tree_fully_interned — includes re_intern_subtree.
test "profile: 20 deep lets - build_tree_fully_interned (ReuseNode)" (b : @bench.T) {
  let source = make_deep_let_chain(20, 10, "x0")
  let (cst, _) = @lambda.parse_cst(source) catch { _ => abort("failed") }
  let events : Array[@seam.ParseEvent] = []
  for child in cst.children {
    match child {
      @seam.CstElement::Token(t) =>
        events.push(@seam.ParseEvent::Token(t.kind, t.text))
      @seam.CstElement::Node(n) =>
        events.push(@seam.ParseEvent::ReuseNode(n))
    }
  }
  let root_kind = cst.kind
  let interner = @seam.Interner::new()
  let ws = @seam.RawKind(11) // WhitespaceToken
  let ni = @seam.NodeInterner::new()
  b.bench(fn() {
    let tree = @seam.build_tree_fully_interned(
      events, root_kind, interner, ni, trivia_kind=Some(ws),
    )
    b.keep(tree)
  })
}

// ─── Closure call overhead isolation ───────────────────────────────────────

///|
/// Measure cost of N closure calls (indirect function calls).
test "profile: closure call overhead - 960 calls" (b : @bench.T) {
  let source = make_profile_source(320, "1")
  let tokens = @lexer.tokenize(source) catch { _ => abort("lex failed") }
  let starts = @core.build_starts(tokens)
  let get_start : (Int) -> Int = fn(i) { starts[i] }
  let n = tokens.length()
  b.bench(fn() {
    let mut sum = 0
    for i = 0; i < n; i = i + 1 {
      sum = sum + get_start(i)
    }
    b.keep(sum)
  })
}

///|
/// Same work via direct array access — no closure indirection.
test "profile: direct array access - 960 calls" (b : @bench.T) {
  let source = make_profile_source(320, "1")
  let tokens = @lexer.tokenize(source) catch { _ => abort("lex failed") }
  let starts = @core.build_starts(tokens)
  let n = tokens.length()
  b.bench(fn() {
    let mut sum = 0
    for i = 0; i < n; i = i + 1 {
      sum = sum + starts[i]
    }
    b.keep(sum)
  })
}
