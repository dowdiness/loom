// Tests for the soft-newline / recovery vocabulary added in Task 6. TestToken /
// TestKind / test_spec are defined in interpreter_test.mbt (shared blackbox
// compilation unit). Each test drives the node through @core.parse_with and
// asserts the diagnostic count it should (or should not) produce.

///|
/// One width-1 token (width-0 for EOF), so a source string of N non-EOF tokens
/// has length N and token offsets stay inside it.
fn tok(t : TestToken) -> @core.TokenInfo[TestToken] {
  @core.TokenInfo::new(t, if t == TestToken::EOF { 0 } else { 1 })
}

///|
/// Parse `tokens` against a one-rule grammar and return the diagnostics. `src`
/// must be as long as the number of non-EOF tokens.
fn vocab_diags(
  rules : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]],
  root : @grammar.RuleName,
  tokens : Array[@core.TokenInfo[TestToken]],
  src : String,
) -> @core.DiagnosticSet raise @grammar.GrammarBuildError {
  let parse_root = @grammar.interpret(@grammar.GrammarIr::GrammarIr(rules, root~))
  let spec = test_spec(parse_root)
  let source_id = @core.SourceId("grammar-vocab-source")
  let (_, diags) = try! @core.parse_with(
    source_id,
    src,
    spec,
    _s => tokens,
    parse_root,
  )
  diags
}

///|
test "Fail emits a diagnostic and an error placeholder" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::Fail("boom"),
  }
  let diags = vocab_diags(rules, "source", [tok(TestToken::EOF)], "")
  inspect(diags.length(), content="1")
}

///|
test "EmitOr emits silently when the token is present" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::EmitOr(TestToken::Int, TestKind::IntToken, "missing int"),
  }
  let diags = vocab_diags(
    rules,
    "source",
    [tok(TestToken::Int), tok(TestToken::EOF)],
    "x",
  )
  inspect(diags.length(), content="0")
}

///|
test "EmitOr reports the token when absent" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::EmitOr(TestToken::Int, TestKind::IntToken, "missing int"),
  }
  let diags = vocab_diags(rules, "source", [tok(TestToken::EOF)], "")
  inspect(diags.length(), content="1")
}

///|
test "DiagnoseIf fires only when the predicate matches the peek" {
  let matching : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::Seq([
      @grammar.Expr::DiagnoseIf(@grammar.Pred::IsToken(TestToken::Int), "found int"),
      @grammar.Expr::Emit(TestToken::Int, TestKind::IntToken),
    ]),
  }
  let diags = vocab_diags(
    matching,
    "source",
    [tok(TestToken::Int), tok(TestToken::EOF)],
    "x",
  )
  inspect(diags.length(), content="1")
  let nonmatching : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::Seq([
      @grammar.Expr::DiagnoseIf(@grammar.Pred::IsToken(TestToken::Word), "found word"),
      @grammar.Expr::Emit(TestToken::Int, TestKind::IntToken),
    ]),
  }
  let diags2 = vocab_diags(
    nonmatching,
    "source",
    [tok(TestToken::Int), tok(TestToken::EOF)],
    "x",
  )
  inspect(diags2.length(), content="0")
}

///|
test "ExpectSkip consumes the soft separator then expects" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::ExpectSkip(
      @grammar.Pred::IsToken(TestToken::Skip),
      TestKind::SkipKind,
      TestToken::Expected,
      TestKind::ExpectedKind,
    ),
  }
  let diags = vocab_diags(
    rules,
    "source",
    [tok(TestToken::Skip), tok(TestToken::Expected), tok(TestToken::EOF)],
    "se",
  )
  inspect(diags.length(), content="0")
}

///|
test "ConsumeGated consumes the run when the lookahead holds" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::Seq([
      @grammar.Expr::ConsumeGated(
        @grammar.Pred::IsToken(TestToken::Skip),
        TestKind::SkipKind,
        @grammar.Pred::IsToken(TestToken::Int),
      ),
      @grammar.Expr::Emit(TestToken::Int, TestKind::IntToken),
    ]),
  }
  let diags = vocab_diags(
    rules,
    "source",
    [tok(TestToken::Skip), tok(TestToken::Int), tok(TestToken::EOF)],
    "si",
  )
  inspect(diags.length(), content="0")
}

///|
test "RequireSep is silent with a separator, diagnoses without one" {
  let rule : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::RequireSep(
      [(TestToken::Skip, TestKind::SkipKind)],
      @grammar.Pred::IsToken(TestToken::EOF),
      @grammar.Pred::Any,
      msg_alt="alt",
      msg_else="else",
    ),
  }
  let with_sep = vocab_diags(
    rule,
    "source",
    [tok(TestToken::Skip), tok(TestToken::EOF)],
    "s",
  )
  inspect(with_sep.length(), content="0")
  let missing : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::Seq([
      @grammar.Expr::RequireSep(
        [(TestToken::Skip, TestKind::SkipKind)],
        @grammar.Pred::IsToken(TestToken::EOF),
        @grammar.Pred::Any,
        msg_alt="alt",
        msg_else="else",
      ),
      @grammar.Expr::Emit(TestToken::Int, TestKind::IntToken),
    ]),
  }
  let without_sep = vocab_diags(
    missing,
    "source",
    [tok(TestToken::Int), tok(TestToken::EOF)],
    "x",
  )
  inspect(without_sep.length(), content="1")
}

///|
/// RequireSep must emit a DISTINCT kind per delimiter token, not collapse the
/// run to one kind — the block-delimiter parity case (newline + `;`). Driven
/// through the REAL interpreter, since the lambda oracle exercises only the
/// probe arm. Self-calibrating: with both delimiters in the table the
/// `Skip Expected` run is fully consumed and the trailing `Int` parses cleanly
/// (0 diagnostics); drop `Expected` from the table and it is left as trailing
/// garbage the EOF guard reports (1 diagnostic) — the single-kind analog of the
/// bug. Distinct kinds landing in the CST is asserted separately by the spike
/// A-vs-B `tree_diff` oracle, through the same shared `consume_while_emit_mapped`.
test "RequireSep consumes a multi-token delimiter run with per-token kinds" {
  fn build(
    delims : Array[(TestToken, TestKind)],
  ) -> Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] {
    {
      "source": @grammar.Expr::Seq([
        @grammar.Expr::RequireSep(
          delims,
          @grammar.Pred::IsToken(TestToken::EOF),
          @grammar.Pred::Any,
          msg_alt="alt",
          msg_else="else",
        ),
        @grammar.Expr::Emit(TestToken::Int, TestKind::IntToken),
        @grammar.Expr::Choice([
          @grammar.Alt::{ starts: @grammar.Pred::IsToken(TestToken::EOF), body: @grammar.Expr::Empty, },
          @grammar.Alt::{
            starts: @grammar.Pred::Any,
            body: @grammar.Expr::ErrorNodeUntil(
              TestKind::Error,
              @grammar.Pred::IsToken(TestToken::EOF),
              "trailing",
            ),
          },
        ]),
      ]),
    }
  }

  let tokens = [
    tok(TestToken::Skip),
    tok(TestToken::Expected),
    tok(TestToken::Int),
    tok(TestToken::EOF),
  ]
  // Both delimiters mapped: the Skip+Expected run is fully consumed, Int parses,
  // EOF guard stays silent.
  let both = vocab_diags(
    build([
      (TestToken::Skip, TestKind::SkipKind),
      (TestToken::Expected, TestKind::ExpectedKind),
    ]),
    "source",
    tokens,
    "sei",
  )
  inspect(both.length(), content="0")
  // Only Skip mapped (the single-kind analog of the bug): Expected stays in the
  // stream, Int never matches, and the EOF guard reports the trailing garbage.
  let single = vocab_diags(
    build([(TestToken::Skip, TestKind::SkipKind)]),
    "source",
    tokens,
    "sei",
  )
  inspect(single.length(), content="1")
}

///|
test "ErrorNodeUntil opens an error node over trailing garbage, EOF-guarded" {
  let guarded : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::Choice([
      @grammar.Alt::{ starts: @grammar.Pred::IsToken(TestToken::EOF), body: @grammar.Expr::Empty, },
      @grammar.Alt::{
        starts: @grammar.Pred::Any,
        body: @grammar.Expr::ErrorNodeUntil(
          TestKind::Error,
          @grammar.Pred::IsToken(TestToken::EOF),
          "unexpected trailing tokens",
        ),
      },
    ]),
  }
  let garbage = vocab_diags(
    guarded,
    "source",
    [tok(TestToken::Int), tok(TestToken::EOF)],
    "x",
  )
  inspect(garbage.length(), content="1")
  let clean = vocab_diags(guarded, "source", [tok(TestToken::EOF)], "")
  inspect(clean.length(), content="0")
}

///|
test "RepeatTopLevel parses every delimited item without diagnostics" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::RepeatTopLevel(
      "word",
      starts=@grammar.Pred::IsToken(TestToken::Word),
      delim=@grammar.Pred::IsToken(TestToken::Skip),
      delim_kind=TestKind::SkipKind,
      between_msg="expected separator between items",
      after_msg="expected separator after item",
    ),
    "word": @grammar.Expr::Node(
      TestKind::WordNode,
      @grammar.Expr::Emit(TestToken::Word, TestKind::WordToken),
    ),
  }
  let diags = vocab_diags(
    rules,
    "source",
    [
      tok(TestToken::Word),
      tok(TestToken::Skip),
      tok(TestToken::Word),
      tok(TestToken::EOF),
    ],
    "wsw",
  )
  inspect(diags.length(), content="0")
}

///|
test "RepeatTopLevel diagnoses a missing delimiter between items" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] = {
    "source": @grammar.Expr::RepeatTopLevel(
      "word",
      starts=@grammar.Pred::IsToken(TestToken::Word),
      delim=@grammar.Pred::IsToken(TestToken::Skip),
      delim_kind=TestKind::SkipKind,
      between_msg="expected separator between items",
      after_msg="expected separator after item",
    ),
    "word": @grammar.Expr::Node(
      TestKind::WordNode,
      @grammar.Expr::Emit(TestToken::Word, TestKind::WordToken),
    ),
  }
  let diags = vocab_diags(
    rules,
    "source",
    [tok(TestToken::Word), tok(TestToken::Word), tok(TestToken::EOF)],
    "ww",
  )
  inspect(diags.length(), content="1")
}

///|
/// Pins the REAL @grammar interpreter's PrattBinary skip behavior — the lambda
/// oracle exercises only the probe, so without this the real arm is unverified.
/// `[Int Skip Word Int]` = operand, soft separator, operator, operand. With
/// `skip=Some`, the gated consume (lookahead = the op table) reaches the
/// operator, the binary forms over all four tokens, EOF follows → 0 diagnostics.
/// With `skip=None` the operator is never reached and `Skip Word Int` is
/// trailing garbage → 1 diagnostic — the pre-fix behavior, which doubles as this
/// test's positive control.
test "PrattBinary skip spans a gated separator before the operator (real interpreter)" {
  let tokens = [
    tok(TestToken::Int),
    tok(TestToken::Skip),
    tok(TestToken::Word),
    tok(TestToken::Int),
    tok(TestToken::EOF),
  ]
  fn rules(
    skip : (@grammar.Pred[TestToken], TestKind)?,
  ) -> Map[@grammar.RuleName, @grammar.Expr[TestToken, TestKind]] {
    {
      "source": @grammar.Expr::Seq([
        @grammar.Expr::Ref("binary"),
        @grammar.Expr::Choice([
          @grammar.Alt::{ starts: @grammar.Pred::IsToken(TestToken::EOF), body: @grammar.Expr::Empty, },
          @grammar.Alt::{
            starts: @grammar.Pred::Any,
            body: @grammar.Expr::ErrorNodeUntil(
              TestKind::Error,
              @grammar.Pred::IsToken(TestToken::EOF),
              "trailing",
            ),
          },
        ]),
      ]),
      "binary": @grammar.Expr::PrattBinary(
        "atom",
        TestKind::WordNode,
        [(TestToken::Word, TestKind::WordToken)],
        skip~,
      ),
      "atom": @grammar.Expr::Emit(TestToken::Int, TestKind::IntToken),
    }
  }

  let with_skip = vocab_diags(
    rules(Some((@grammar.Pred::IsToken(TestToken::Skip), TestKind::SkipKind))),
    "source",
    tokens,
    "iswi",
  )
  inspect(with_skip.length(), content="0")
  let without_skip = vocab_diags(rules(None), "source", tokens, "iswi")
  inspect(without_skip.length(), content="1")
}
