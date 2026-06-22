// Issue #444 §6 decision gate: INCREMENTAL EDIT THROUGHPUT of the @grammar
// interpreter-driven lambda parser (B) vs the hand-written recursive-descent
// lambda parser (A).
//
// The metric is `apply_edit` cycles (NOT fresh full-parse) — the spec (§6/§D)
// explicitly refuses to assume monogram's analyze-once speedup carries to an
// incremental engine, so this benchmark measures the genuinely-open question.
//
// FAIRNESS BY CONSTRUCTION: both A and B are built through the spike's
// `normalized_syntax_grammar`, which pins `incremental_relex_enabled=false` and
// `block_reparse_spec=None`. The ONLY thing that differs between the two parsers
// is `spec.parse_root` — A's hand parser vs B's `@grammar.compile(...)` +
// tree-walking interpreter. Any throughput delta is attributable to the
// interpreter, not parser config. (Same driving as the D1/D2a/D2b oracle:
// `new_syntax_parser` + `apply_edit` + force-read `snapshot()`.)
//
// Run with:
//   cd examples/lambda && NEW_MOON_MOD=0 moon bench --release \
//     -p dowdiness/lambda/benchmarks -f grammar_incremental_benchmark.mbt

// ── Grammar builders (A and B share the normalizer) ─────────────────

///|
/// A: hand-written lambda parser, normalized to B's incremental config.
fn build_a() -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] {
  @spike.normalized_syntax_grammar(
    @lambda.lambda_grammar.spec,
    @lambda.lambda_grammar.lex,
  )
}

///|
/// B: reified @grammar IR compiled to dense slots + interpreted.
fn build_b() -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] {
  @spike.build_b_syntax_grammar() catch {
    _ => abort("B grammar failed to compile")
  }
}

// ── Edit session generator ──────────────────────────────────────────

///|
/// A balanced typing session over `base`: type " + 1" char-by-char at the end,
/// then delete it char-by-char. The session is NET-NEUTRAL (it ends at `base`),
/// so each bench iteration starts from identical source AND the incremental
/// parser's last-good baseline is restored between iterations.
///
/// Eight distinct edits (4 inserts at a growing offset, 4 deletes at a shrinking
/// offset) vary the operand across the loop, so JIT branch caching of one hot
/// edit cannot deflate the measured per-edit cost (perf-skill rule). Each step is
/// `(edit, source_after)`, ready to replay through `apply_edit`.
fn make_edit_session(base : String) -> Array[(@core.Edit, String)] {
  let steps : Array[(@core.Edit, String)] = []
  let mut s = base
  for ch in [" ", "+", " ", "1"] {
    let (next, edit) = apply_char_insert(s, s.length(), ch)
    steps.push((edit, next))
    s = next
  }
  for _i in 0..<4 {
    let pos = s.length() - 1
    let edit = @core.Edit::delete(pos, pos + 1)
    let next = slice(s, 0, pos)
    steps.push((edit, next))
    s = next
  }
  steps
}

// ── Validity guard: B must actually reuse on a tail edit ────────────
// The incremental-throughput parity below is only meaningful if B does real
// incremental work. If B silently full-reparsed every edit, its per-edit cost
// could still coincidentally resemble A's — so assert B reuses, and reuses as
// much as A (reuse parity is the *mechanism* that makes the interpreter's
// full-parse overhead amortize away on edits).

///|
test "grammar A and B reuse comparably on a tail edit (throughput parity mechanism)" {
  let source = make_let_chain(80, "0")
  let session = make_edit_session(source)
  let a = @loom.new_syntax_parser(source, build_a())
  let b = @loom.new_syntax_parser(source, build_b())
  let _ = a.snapshot().read_or_abort()
  let _ = b.snapshot().read_or_abort()
  // Apply the first edit (insert a char at the tail) to both.
  let (first_edit, after) = session[0]
  a.apply_edit(first_edit, after)
  b.apply_edit(first_edit, after)
  let a_reuse = a.snapshot().read_or_abort().reuse_count
  let b_reuse = b.snapshot().read_or_abort().reuse_count
  println("tail-edit reuse: A=\{a_reuse} B=\{b_reuse}")
  // B must reuse (real incremental path), and match A (reuse parity).
  assert_true(b_reuse > 0)
  assert_eq(a_reuse, b_reuse)
}

///|
test "grammar A and B reuse comparably on a DEEP-subtree edit (deep-tier honesty)" {
  // The deep-tree tier's ~1.15–2.4x B/A could mean either (benign) per-node
  // interpret overhead at equal reuse, or (serious) B reusing LESS than A. Check
  // reuse on the first deep flip so the deep-tier number is read correctly.
  let source = make_lambda_let_chain(20)
  let session = make_deep_tree_session(source)
  let a = @loom.new_syntax_parser(source, build_a())
  let b = @loom.new_syntax_parser(source, build_b())
  let _ = a.snapshot().read_or_abort()
  let _ = b.snapshot().read_or_abort()
  let (deep_edit, after) = session[0]
  a.apply_edit(deep_edit, after)
  b.apply_edit(deep_edit, after)
  let a_reuse = a.snapshot().read_or_abort().reuse_count
  let b_reuse = b.snapshot().read_or_abort().reuse_count
  println("deep-edit reuse: A=\{a_reuse} B=\{b_reuse}")
  // FINDING (ADR 2026-06-22): on a deep-subtree edit the hand parser reuses
  // subtrees the interpreter does NOT — B's reuse granularity is coarser than
  // A's on nested structures. reuse_count alone would be weak evidence (the spec
  // §6 flags it as "vacuous" — engine node reuse can mask repeat-group gaps), so
  // the deep FULL-parse control benchmark below corroborates it by wall clock:
  // across 3 runs B's deep PER-EDIT cost ≈ its full-parse cost (per-edit/full =
  // 1.23, 1.03, 0.97 → B re-parses the whole deep tree each edit), whereas A's
  // deep per-edit is ≪ its full-parse (0.70, 0.29, 0.49 → A reuses). That gap is
  // the *cause* of the deep-tier ~1.15–2.4x B/A slowdown — a real, mechanism-
  // confirmed reuse deficiency, not a slower-per-node constant factor. Guard it:
  // A reuses, and B reuses strictly less. If B's reuse is later improved this
  // test SHOULD fail — revisit the ADR's graduate-with-caveat verdict when it does.
  assert_true(a_reuse > 0)
  assert_true(b_reuse < a_reuse)
}

///|
test "grammar A and B reuse on a FLAT in-place edit (is the gap general?)" {
  // Tier 2's session appends at the buffer END (low reuse for both: A=1 B=1).
  // The high-reuse flat case is an IN-PLACE literal edit to one def among 80 —
  // here A should reuse the other 79. Does B? This decides whether the reuse
  // gap is deep-subtree-specific or general.
  let source = make_let_chain(80, "0")
  guard source.find("x40 = 0") is Some(at) else { abort("x40 not found") }
  let pos = at + "x40 = ".length() // the literal `0` of def x40
  let after = slice(source, 0, pos) +
    "1" +
    slice(source, pos + 1, source.length())
  let edit = @core.Edit::replace(pos, pos + 1, pos + 1)
  let a = @loom.new_syntax_parser(source, build_a())
  let b = @loom.new_syntax_parser(source, build_b())
  let _ = a.snapshot().read_or_abort()
  let _ = b.snapshot().read_or_abort()
  a.apply_edit(edit, after)
  b.apply_edit(edit, after)
  let a_reuse = a.snapshot().read_or_abort().reuse_count
  let b_reuse = b.snapshot().read_or_abort().reuse_count
  println("flat in-place reuse: A=\{a_reuse} B=\{b_reuse}")
  assert_true(a_reuse > 0)
}

// ── Tier 1: Initial parse (context — where does B's overhead live?) ──

///|
test "grammar A (hand): let-chain 80 - initial parse" (b : @bench.T) {
  let source = make_let_chain(80, "0")
  let grammar = build_a()
  b.bench(fn() {
    let parser = @loom.new_syntax_parser(source, grammar)
    b.keep(parser.snapshot().read_or_abort())
  })
}

///|
test "grammar B (interp): let-chain 80 - initial parse" (b : @bench.T) {
  let source = make_let_chain(80, "0")
  let grammar = build_b()
  b.bench(fn() {
    let parser = @loom.new_syntax_parser(source, grammar)
    b.keep(parser.snapshot().read_or_abort())
  })
}

// ── Control: deep-doc FULL parse (does B full-reparse deep edits?) ──
// Discriminates the deep-tier mechanism: compare B's deep PER-EDIT cost
// (Tier 3) against B's deep FULL-parse here. per-edit ≈ full-parse ⇒ B genuinely
// full-reparses deep edits (reuse deficiency); per-edit ≪ full-parse ⇒ B reuses
// despite reuse_count=0 (the count is the spec's "vacuous" artifact) and the
// slowdown is constant-factor density, not lost reuse.

///|
test "grammar A (hand): deep lambda tree - full parse" (b : @bench.T) {
  let source = make_lambda_let_chain(20)
  let grammar = build_a()
  b.bench(fn() {
    let parser = @loom.new_syntax_parser(source, grammar)
    b.keep(parser.snapshot().read_or_abort())
  })
}

///|
test "grammar B (interp): deep lambda tree - full parse" (b : @bench.T) {
  let source = make_lambda_let_chain(20)
  let grammar = build_b()
  b.bench(fn() {
    let parser = @loom.new_syntax_parser(source, grammar)
    b.keep(parser.snapshot().read_or_abort())
  })
}

// ── Tier 2: Incremental edit session (THE decision metric) ──────────
// Parser built ONCE outside the bench loop; the initial parse is forced once,
// unmeasured. Each measured iteration replays the 8-edit balanced session,
// forcing the incremental parse after every edit. This isolates `apply_edit`
// throughput from initial-parse cost.

///|
test "grammar A (hand): let-chain 80 - incremental edit session (8 edits)" (
  b : @bench.T,
) {
  let source = make_let_chain(80, "0")
  let session = make_edit_session(source)
  let parser = @loom.new_syntax_parser(source, build_a())
  b.keep(parser.snapshot().read_or_abort())
  b.bench(fn() {
    for step in session {
      let (edit, after) = step
      parser.apply_edit(edit, after)
      b.keep(parser.snapshot().read_or_abort())
    }
  })
}

///|
test "grammar B (interp): let-chain 80 - incremental edit session (8 edits)" (
  b : @bench.T,
) {
  let source = make_let_chain(80, "0")
  let session = make_edit_session(source)
  let parser = @loom.new_syntax_parser(source, build_b())
  b.keep(parser.snapshot().read_or_abort())
  b.bench(fn() {
    for step in session {
      let (edit, after) = step
      parser.apply_edit(edit, after)
      b.keep(parser.snapshot().read_or_abort())
    }
  })
}

// ── Tier 3 (robustness): deep nested-lambda tree ────────────────────
// The flat let-chain (Tier 2) is the MAX-reuse / MIN-interpreter-exposure case:
// a tail edit re-parses one shallow definition. To stress the parity verdict
// where it is weakest, this tier uses a deep nested-lambda document
// (make_lambda_let_chain): each definition is
// `let xN = ((f, x) => f (f x)) ((g) => g)`, ~6-8 CST nodes deep, so the
// reuse-cursor walk is O(depth) and the re-parsed region per edit is a larger
// subtree — the regime where the interpreter's per-node tree-walk + Pred::test
// dispatch could plausibly diverge from A's inlined hand code.

///|
/// Build the balanced edit session for the deep nested-lambda workload.
///
/// Flips four DEEP leaves of the last nested-lambda definition (the body `g` and
/// param `g` of `((g) => g)`, and the inner `x`/`f` of `(f x)`), each as a
/// 1-char→1-char `replace` immediately undone. Because every edit is
/// length-preserving the offsets never shift, and undoing each flip makes the
/// session net-neutral (ends at `base`) so the parser baseline resets between
/// bench iterations — mirroring `make_edit_session`'s contract.
///
/// Positions are anchored with `rev_find` on the last `((g) => g)` / `(f x)`
/// substrings, so they are independent of `make_lambda_let_chain`'s count digit
/// width. The four sites span two nested lambda bodies + a nested application,
/// exercising the O(depth) reuse-cursor walk where the interpreter's per-node
/// tree-walk could diverge from A's inlined hand code.
fn make_deep_tree_session(base : String) -> Array[(@core.Edit, String)] {
  guard base.rev_find("((g) => g)") is Some(lam) else {
    abort("deep-tree session: '((g) => g)' not found")
  }
  guard base.rev_find("(f x)") is Some(app) else {
    abort("deep-tree session: '(f x)' not found")
  }
  // (offset, expected current char, flipped char) for four distinct deep leaves.
  let flips : Array[(Int, String, String)] = [
    (lam + 8, "g", "h"), // deepest: body of `(g) => g`
    (lam + 2, "g", "h"), // param of `(g) => g`
    (app + 3, "x", "y"), // arg of nested application `(f x)`
    (app + 1, "f", "h"), // fn  of nested application `(f x)`
  ]
  let steps : Array[(@core.Edit, String)] = []
  let mut s = base
  for flip in flips {
    let (pos, from, to) = flip
    guard slice(s, pos, pos + 1) == from else {
      abort("deep-tree session: expected '\{from}' at \{pos}")
    }
    let same_len = @core.Edit::replace(pos, pos + 1, pos + 1)
    let forward = slice(s, 0, pos) + to + slice(s, pos + 1, s.length())
    steps.push((same_len, forward))
    s = forward
    let backward = slice(s, 0, pos) + from + slice(s, pos + 1, s.length())
    steps.push((same_len, backward))
    s = backward
  }
  steps
}

///|
test "grammar A (hand): deep lambda tree - incremental edit session" (
  b : @bench.T,
) {
  let source = make_lambda_let_chain(20)
  let session = make_deep_tree_session(source)
  let parser = @loom.new_syntax_parser(source, build_a())
  b.keep(parser.snapshot().read_or_abort())
  b.bench(fn() {
    for step in session {
      let (edit, after) = step
      parser.apply_edit(edit, after)
      b.keep(parser.snapshot().read_or_abort())
    }
  })
}

///|
test "grammar B (interp): deep lambda tree - incremental edit session" (
  b : @bench.T,
) {
  let source = make_lambda_let_chain(20)
  let session = make_deep_tree_session(source)
  let parser = @loom.new_syntax_parser(source, build_b())
  b.keep(parser.snapshot().read_or_abort())
  b.bench(fn() {
    for step in session {
      let (edit, after) = step
      parser.apply_edit(edit, after)
      b.keep(parser.snapshot().read_or_abort())
    }
  })
}
