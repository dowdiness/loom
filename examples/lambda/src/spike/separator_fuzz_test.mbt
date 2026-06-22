///|
/// Separator fuzzer: a differential test that drives parser A (hand-written
/// `@lambda.parse_cst`) and parser B (grammar-interpreted, via the probe-backed
/// `build_b_syntax_grammar`) over the same generated programs and asserts D2a
/// parity — identical CST (`@core.tree_diff` empty) and structurally identical
/// diagnostics.
///
/// Why a *separator* fuzzer and not a random-program / AST generator: every
/// A-vs-B divergence found so far (`1\n+ 2`, `fn f() { x = 1; y = 2 }`, the soft
/// newline before `=`) lives in the delimiter/whitespace-placement layer, not
/// the structural layer. An AST→source renderer would normalize that whitespace
/// away and delete the very trigger. So we generate at the lexical layer: fixed
/// program skeletons with separator *slots*, and `expand` fans each slot out
/// over the cartesian product of its alternatives.
///
/// Scope (v1): well-formed programs only. The active detector is the CST diff —
/// `diagnostics_structurally_equal` asserts only that A and B *agree* on
/// diagnostics (expected: none for well-formed inputs), so it is latent here and
/// earns its keep once v2 adds malformed inputs. Malformed-input fuzzing is a
/// follow-up — it would force tolerating the known message-wording
/// `ReplicationResidual` on recovery paths.
///
/// This broadens A-vs-B coverage beyond the hand-written fixtures (whose absence
/// on these paths was the root cause of the three CodeRabbit findings). It does
/// NOT pin the real `@grammar` interpreter for lambda — B runs through the spike
/// probe (because of the `ManualNewlineAppExpr` residue); pinning the real
/// interpreter stays the job of `@grammar`'s `vocab_test` and the E3 grammar.

///|
/// A program-skeleton segment: either fixed source text (`Lit`) or a separator
/// slot (`Sep`) whose alternatives `expand` fans out. A skeleton is an
/// `Array[Seg]`; its expansion is the cartesian product over every `Sep` slot.
///
/// Mechanism example — two programs differing only in the separator before `=`:
///   [Lit("let x ="), Sep([" ", "\n"]), Lit(" 1")]
/// expands to ["let x = 1", "let x =\n 1"].
enum Seg {
  Lit(String)
  Sep(Array[String])
}

///|
/// Fan a skeleton out into every concrete program: the cartesian product over
/// its `Sep` slots, with `Lit` text fixed. A skeleton with no `Sep` slots yields
/// exactly one program.
fn expand(segs : Array[Seg]) -> Array[String] {
  segs.fold(init=[""], (acc, seg) => {
    match seg {
      Lit(s) => acc.map(p => p + s)
      Sep(alts) =>
        acc.iter().flat_map(p => alts.iter().map(a => p + a)).collect()
    }
  })
}

///|
/// The separator-fuzz corpus: program skeletons whose `Sep` slots vary the
/// delimiter/whitespace alphabet. `expand` takes the cartesian product, so each
/// skeleton stands for every combination of its separator choices.
fn fuzz_skeletons() -> Array[Array[Seg]] {
  // Separator alphabets, one per divergence-prone axis. Each MUST contain its
  // historically-divergent choice or the test goes hollow on that axis.
  let op = [" + ", "\n+ ", "+", " - ", "\n- "] // "\n+ " = PrattBinary soft-newline bug (#3)
  let block_sep = ["\n", ";", " ; ", "\n\n", ";\n", "\n;"] // ";" = RequireSep semicolon bug (#4)
  let pad = [" ", "\n"] // space vs soft newline (around "=", "{"/"}", app atoms)
  let top_sep = ["\n", "\n\n"] // top level accepts newline only — no ";"
  [
    // 1. let RHS + binary operator: soft newline before RHS and before the op.
    [Lit("let x ="), Sep(pad), Lit("1"), Sep(op), Lit("2")],
    // 2. block with two defs: the newline/semicolon delimiter run (and runs of 2).
    [
      Lit("fn f() {"),
      Sep(pad),
      Lit("let x = 1"),
      Sep(block_sep),
      Lit("let y = 2"),
      Sep(pad),
      Lit("}"),
    ],
    // 3. top-level application atoms: the newline-app residue (probe path).
    [Lit("f"), Sep(pad), Lit("x")],
    // 4. two top-level defs: RepeatTopLevel separator (newline-only parity).
    [Lit("let x = 1"), Sep(top_sep), Lit("let y = 2")],
    // 5. soft newline on both sides of "=".
    [Lit("let x"), Sep(pad), Lit("="), Sep(pad), Lit("1")],
  ]
}

///|
/// Render a source for a failure message with newlines/tabs escaped, so `\n` vs
/// `\n\n` vs `\n ` — the exact distinctions this test exists to surface — stay
/// visible on one line in CI output.
fn show_source(s : String) -> String {
  s.replace_all(old="\n", new="\\n").replace_all(old="\t", new="\\t")
}

///|
test "separator fuzz: A-vs-B parity over delimiter/whitespace variations" {
  let programs : Array[String] = fuzz_skeletons()
    .iter()
    .flat_map(s => expand(s).iter())
    .collect()
  // A vacuous corpus is a silent failure: a fuzzer that generates nothing
  // passes trivially. Refuse to "pass" on an empty program set.
  guard programs.length() > 0 else {
    fail("separator fuzzer produced no programs")
  }
  let b_grammar = build_b_syntax_grammar()
  for source in programs {
    let (a_cst, a_diag) = @lambda.parse_cst(source)
    let (b_cst, b_diag) = b_grammar.parse_cst(source)
    let cst_diff = @core.tree_diff(a_cst, b_cst)
    guard cst_diff.is_empty() else {
      fail(
        "A-vs-B CST divergence (\{cst_diff.length()} diffs) on source [\{show_source(source)}]",
      )
    }
    guard diagnostics_structurally_equal(a_diag, b_diag) else {
      fail("A-vs-B diagnostic divergence on source [\{show_source(source)}]")
    }
  }
}
