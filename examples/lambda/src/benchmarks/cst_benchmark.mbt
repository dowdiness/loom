// Focused microbenchmarks for CST construction, equality/hash fast paths,
// and token interning (baseline for future node-interning evaluation).
// Run with: moon bench --package dowdiness/loom/benchmarks --release

///|
fn make_ident_token(text : String) -> @seam.CstToken {
  @seam.CstToken::new(@seam.RawKind(9), text)
}

///|
fn make_flat_ident_node(count : Int) -> @seam.CstNode {
  let children : Array[@seam.CstElement] = []
  for i = 0; i < count; i = i + 1 {
    children.push(
      @seam.CstElement::Token(make_ident_token("x" + i.to_string())),
    )
  }
  @seam.CstNode::new(@seam.RawKind(20), children)
}

///|
/// Benchmark: CstToken constructor (includes token hash computation).
test "concrete-syntax-tree - token constructor" (b : @bench.T) {
  b.bench(fn() {
    let t = make_ident_token("identifier_123")
    b.keep(t)
  })
}

///|
/// Benchmark: CstNode constructor over prebuilt children (hash fold cost).
test "concrete-syntax-tree - node constructor from 32 children" (b : @bench.T) {
  let children : Array[@seam.CstElement] = []
  for i = 0; i < 32; i = i + 1 {
    children.push(
      @seam.CstElement::Token(make_ident_token("x" + i.to_string())),
    )
  }
  b.bench(fn() {
    let n = @seam.CstNode::new(@seam.RawKind(20), children)
    b.keep(n)
  })
}

///|
/// Benchmark: Equality on identical trees (hash check + deep structural walk).
test "concrete-syntax-tree - equality identical 32 children" (b : @bench.T) {
  let left = make_flat_ident_node(32)
  let right = make_flat_ident_node(32)
  b.bench(fn() {
    let same = left == right
    b.keep(same)
  })
}

///|
/// Benchmark: Equality on different trees (hash fast path should fail early).
test "concrete-syntax-tree - equality mismatch hash fast path" (b : @bench.T) {
  let left = make_flat_ident_node(32)
  let children : Array[@seam.CstElement] = []
  for i = 0; i < 32; i = i + 1 {
    let text = if i == 31 { "changed_tail" } else { "x" + i.to_string() }
    children.push(@seam.CstElement::Token(make_ident_token(text)))
  }
  let right = @seam.CstNode::new(@seam.RawKind(20), children)
  b.bench(fn() {
    let same = left == right
    b.keep(same)
  })
}

// --- Token interning benchmarks ---
// Baseline measurements for token interning overhead and deduplication benefit.
// Used as the reference point before evaluating whether node interning is worthwhile.
//
// SyntaxKind mappings used here:
//   9  = IdentToken     14 = LambdaExpr    19 = IntLiteral
//   10 = IntToken       15 = AppExpr       20 = VarRef
//   11 = WhitespaceToken  16 = BinaryExpr  22 = SourceFile (root)
//   4  = PlusToken

///|
/// Events for "x + 1": BinaryExpr(VarRef(x), +, IntLiteral(1)) under SourceFile root.
fn make_x_plus_1_events() -> Array[@seam.ParseEvent] {
  [
    @seam.ParseEvent::StartNode(@seam.RawKind(16)), // BinaryExpr
    @seam.ParseEvent::StartNode(@seam.RawKind(20)), // VarRef
    @seam.ParseEvent::Token(@seam.RawKind(9), "x"),
    @seam.ParseEvent::FinishNode,
    @seam.ParseEvent::Token(@seam.RawKind(11), " "),
    @seam.ParseEvent::Token(@seam.RawKind(4), "+"),
    @seam.ParseEvent::Token(@seam.RawKind(11), " "),
    @seam.ParseEvent::StartNode(@seam.RawKind(19)), // IntLiteral
    @seam.ParseEvent::Token(@seam.RawKind(10), "1"),
    @seam.ParseEvent::FinishNode,
    @seam.ParseEvent::FinishNode,
  ]
}

///|
/// Benchmark: Interner::intern_token - cold miss path (token not yet in table).
/// Measures HashMap insert + key string alloc + CstToken::new.
test "interner - intern_token cold miss" (b : @bench.T) {
  b.bench(fn() {
    let interner = @seam.Interner::new()
    let t = interner.intern_token(@seam.RawKind(9), "identifier_123")
    b.keep(t)
  })
}

///|
/// Benchmark: Interner::intern_token - warm hit path (token already cached).
/// Measures only HashMap lookup + key string alloc; no CstToken allocation.
test "interner - intern_token warm hit" (b : @bench.T) {
  let interner = @seam.Interner::new()
  let _ = interner.intern_token(@seam.RawKind(9), "identifier_123")
  b.bench(fn() {
    let t = interner.intern_token(@seam.RawKind(9), "identifier_123")
    b.keep(t)
  })
}

///|
/// Benchmark: build_tree on "x + 1" (no interning, allocates fresh tokens each call).
test "build_tree - x + 1" (b : @bench.T) {
  let events = make_x_plus_1_events()
  b.bench(fn() {
    let tree = try! @seam.build_tree(events, @seam.RawKind(22))
    b.keep(tree)
  })
}

///|
/// Benchmark: build_tree_interned on "x + 1" with a cold interner (first parse).
/// Overhead = warm-hit benchmark + miss cost for each distinct token.
test "build_tree_interned - x + 1, cold interner" (b : @bench.T) {
  let events = make_x_plus_1_events()
  b.bench(fn() {
    let interner = @seam.Interner::new()
    let tree = try! @seam.build_tree_interned(
      events,
      @seam.RawKind(22),
      interner,
    )
    b.keep(tree)
  })
}

///|
/// Benchmark: build_tree_interned on "x + 1" with a warm interner (subsequent parses).
/// Models steady-state: all tokens already cached, every Token event is a hit.
test "build_tree_interned - x + 1, warm interner" (b : @bench.T) {
  let events = make_x_plus_1_events()
  let interner = @seam.Interner::new()
  let _ = try! @seam.build_tree_interned(events, @seam.RawKind(22), interner)
  b.bench(fn() {
    let tree = try! @seam.build_tree_interned(
      events,
      @seam.RawKind(22),
      interner,
    )
    b.keep(tree)
  })
}

///|
fn make_repeated_ident_events(count : Int) -> Array[@seam.ParseEvent] {
  let events : Array[@seam.ParseEvent] = []
  for i = 0; i < count; i = i + 1 {
    events.push(@seam.ParseEvent::Token(@seam.RawKind(9), "x"))
  }
  events
}

///|
/// Benchmark: build_tree with 100 identical ident tokens (100 CstToken::new calls).
/// Upper bound on token-level savings from interning when all tokens are identical.
test "build_tree - 100 identical ident tokens" (b : @bench.T) {
  let events = make_repeated_ident_events(100)
  b.bench(fn() {
    let tree = try! @seam.build_tree(events, @seam.RawKind(22))
    b.keep(tree)
  })
}

///|
/// Benchmark: build_tree_interned with 100 identical ident tokens, warm interner.
/// 1 miss + 99 hits; shows maximum deduplication benefit for tokens.
test "build_tree_interned - 100 identical tokens, warm interner" (b : @bench.T) {
  let events = make_repeated_ident_events(100)
  let interner = @seam.Interner::new()
  let _ = try! @seam.build_tree_interned(events, @seam.RawKind(22), interner)
  b.bench(fn() {
    let tree = try! @seam.build_tree_interned(
      events,
      @seam.RawKind(22),
      interner,
    )
    b.keep(tree)
  })
}

// --- Node interning benchmarks ---
// Measure overhead and deduplication benefit of NodeInterner (build_tree_fully_interned).

///|
/// Events for a nested tree: BinaryExpr(VarRef(x), +, VarRef(x)) — two identical subtrees.
fn make_x_plus_x_events() -> Array[@seam.ParseEvent] {
  [
    @seam.ParseEvent::StartNode(@seam.RawKind(16)), // BinaryExpr
    @seam.ParseEvent::StartNode(@seam.RawKind(20)), // VarRef
    @seam.ParseEvent::Token(@seam.RawKind(9), "x"),
    @seam.ParseEvent::FinishNode,
    @seam.ParseEvent::Token(@seam.RawKind(11), " "),
    @seam.ParseEvent::Token(@seam.RawKind(4), "+"),
    @seam.ParseEvent::Token(@seam.RawKind(11), " "),
    @seam.ParseEvent::StartNode(@seam.RawKind(20)), // VarRef
    @seam.ParseEvent::Token(@seam.RawKind(9), "x"),
    @seam.ParseEvent::FinishNode,
    @seam.ParseEvent::FinishNode,
  ]
}

///|
/// Benchmark: build_tree_fully_interned on "x + x", cold interners (first parse).
test "build_tree_fully_interned - x + x, cold" (b : @bench.T) {
  let events = make_x_plus_x_events()
  b.bench(fn() {
    let interner = @seam.Interner::new()
    let ni = @seam.NodeInterner::new()
    let tree = try! @seam.build_tree_fully_interned(
      events,
      @seam.RawKind(22),
      interner,
      ni,
    )
    b.keep(tree)
  })
}

///|
/// Benchmark: build_tree_fully_interned on "x + x", warm interners (subsequent parses).
/// Both VarRef(x) nodes should hit the NodeInterner on second build.
test "build_tree_fully_interned - x + x, warm" (b : @bench.T) {
  let events = make_x_plus_x_events()
  let interner = @seam.Interner::new()
  let ni = @seam.NodeInterner::new()
  let _ = try! @seam.build_tree_fully_interned(
    events,
    @seam.RawKind(22),
    interner,
    ni,
  )
  b.bench(fn() {
    let tree = try! @seam.build_tree_fully_interned(
      events,
      @seam.RawKind(22),
      interner,
      ni,
    )
    b.keep(tree)
  })
}

///|
/// Benchmark: build_tree_interned (token only) on "x + x" for comparison.
test "build_tree_interned - x + x, warm" (b : @bench.T) {
  let events = make_x_plus_x_events()
  let interner = @seam.Interner::new()
  let _ = try! @seam.build_tree_interned(events, @seam.RawKind(22), interner)
  b.bench(fn() {
    let tree = try! @seam.build_tree_interned(
      events,
      @seam.RawKind(22),
      interner,
    )
    b.keep(tree)
  })
}

///|
/// Benchmark: build_tree (no interning) on "x + x" for baseline.
test "build_tree - x + x" (b : @bench.T) {
  let events = make_x_plus_x_events()
  b.bench(fn() {
    let tree = try! @seam.build_tree(events, @seam.RawKind(22))
    b.keep(tree)
  })
}

///|
/// Benchmark: NodeInterner::intern_node cold miss.
test "node_interner - intern_node cold miss" (b : @bench.T) {
  b.bench(fn() {
    let ni = @seam.NodeInterner::new()
    let node = @seam.CstNode::new(@seam.RawKind(20), [
      @seam.CstElement::Token(make_ident_token("x")),
    ])
    let r = ni.intern_node(node)
    b.keep(r)
  })
}

///|
/// Benchmark: NodeInterner::intern_node warm hit.
test "node_interner - intern_node warm hit" (b : @bench.T) {
  let ni = @seam.NodeInterner::new()
  let node = @seam.CstNode::new(@seam.RawKind(20), [
    @seam.CstElement::Token(make_ident_token("x")),
  ])
  let _ = ni.intern_node(node)
  b.bench(fn() {
    let node2 = @seam.CstNode::new(@seam.RawKind(20), [
      @seam.CstElement::Token(make_ident_token("x")),
    ])
    let r = ni.intern_node(node2)
    b.keep(r)
  })
}

///|
/// Benchmark: Full parse_cst end-to-end (global interning always active).
test "parse_cst - end-to-end" (b : @bench.T) {
  b.bench(fn() {
    let result = @lambda.parse_cst("λf.λx.f (f x)") catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}
