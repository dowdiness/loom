///|
/// Constrained differential fuzzer for newline-application mode switches.
///
/// We generate only sources where the initial top-level trailing expression is in
/// the spike probe's newline-application mode, then apply the same prefix insert
/// (`let a = `) that moves that expression into let-body mode. Each case checks:
///
/// 1. seed comparability: fresh A CST == fresh B CST on the initial source
/// 2. B-only D1: incremental B == fresh B on the edited source
/// 3. A-vs-B parity after the edit: incremental A CST/diagnostics == incremental B
///
/// This keeps the generator at the lexical/context layer where the suspected bug
/// lives, rather than normalizing it away via AST generation.
enum ModeSeg {
  Lit(String)
  Sep(Array[String])
}

///|
fn mode_expand(segs : Array[ModeSeg]) -> Array[String] {
  segs.fold(init=[""], (acc, seg) => {
    match seg {
      Lit(s) => acc.map(p => p + s)
      Sep(alts) =>
        acc.iter().flat_map(p => alts.iter().map(a => p + a)).collect()
    }
  })
}

///|
fn mode_switch_skeletons() -> Array[Array[ModeSeg]] {
  let op = [" + ", "\n+ ", "+", " - ", "\n- "]
  let atom_sep = [" ", "\n"]
  [
    // Top-level newline-app expression with binary continuation.
    [Lit("f"), Sep(atom_sep), Lit("x"), Sep(op), Lit("1")],
    // Top-level newline-app application chain.
    [Lit("f"), Sep(atom_sep), Lit("x"), Sep(atom_sep), Lit("y")],
  ]
}

///|
fn mode_show_source(s : String) -> String {
  s.replace_all(old="\n", new="\\n").replace_all(old="\t", new="\\t")
}

///|
test "mode-switch fuzz: prefix let insert preserves B D1 and A/B parity" {
  let programs : Array[String] = mode_switch_skeletons()
    .iter()
    .flat_map(s => mode_expand(s).iter())
    .collect()
  guard programs.length() > 0 else {
    fail("mode-switch fuzzer produced no programs")
  }

  let a_grammar = normalized_syntax_grammar(
    @lambda.lambda_grammar.spec,
    @lambda.lambda_grammar.lex,
  )
  let b_grammar = build_b_syntax_grammar()

  for initial in programs {
    let after = "let a = " + initial
    let edit = @core.Edit::insert(0, "let a = ".length())

    let (a_seed, a_seed_diag) = @lambda.parse_cst(initial)
    let (b_seed, b_seed_diag) = b_grammar.parse_cst(initial)
    guard @core.tree_diff(a_seed, b_seed).is_empty() else {
      fail("seed CST divergence on source [\{mode_show_source(initial)}]")
    }
    guard diagnostics_structurally_equal(a_seed_diag, b_seed_diag) else {
      fail(
        "seed diagnostic divergence on source [\{mode_show_source(initial)}]",
      )
    }

    let a_parser = @loom.new_syntax_parser(initial, a_grammar)
    let b_parser = @loom.new_syntax_parser(initial, b_grammar)
    a_parser.apply_edit(edit, after)
    b_parser.apply_edit(edit, after)
    let a_snap = a_parser.snapshot().read_or_abort()
    let b_snap = b_parser.snapshot().read_or_abort()

    let (fresh_b_cst, fresh_b_diag) = b_grammar.parse_cst(after)
    guard @core.tree_diff(b_snap.syntax.cst_node(), fresh_b_cst).is_empty() else {
      fail(
        "B D1 CST divergence after prefix insert on source [\{mode_show_source(initial)}]",
      )
    }
    guard b_snap.diagnostics == fresh_b_diag else {
      fail(
        "B D1 diagnostics divergence after prefix insert on source [\{mode_show_source(initial)}]",
      )
    }

    guard @core.tree_diff(a_snap.syntax.cst_node(), b_snap.syntax.cst_node()).is_empty() else {
      fail(
        "A/B incremental CST divergence after prefix insert on source [\{mode_show_source(initial)}]",
      )
    }
    guard diagnostics_structurally_equal(a_snap.diagnostics, b_snap.diagnostics) else {
      fail(
        "A/B incremental diagnostics divergence after prefix insert on source [\{mode_show_source(initial)}]",
      )
    }
  }
}
